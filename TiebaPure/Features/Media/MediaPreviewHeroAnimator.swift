import UIKit

enum MediaPreviewHeroOperation {
    case presentation
    case dismissal
}

struct MediaPreviewHeroDismissalContent {
    let image: UIImage
    let frame: CGRect
}

@MainActor
protocol MediaPreviewHeroTransitionParticipant: AnyObject {
    var mediaPreviewHeroSourceIdentity: String? { get }

    func mediaPreviewStableSourceView(
        in sourceViewController: UIViewController
    ) -> ImagePreviewSourceView?

    /// Returns nil when dismissal must cross-dissolve instead of returning a
    /// bitmap to the source thumbnail.
    func mediaPreviewHeroDismissalContent(
        sourceView: ImagePreviewSourceView,
        dismissedView: UIView,
        containerView: UIView
    ) -> MediaPreviewHeroDismissalContent?

    func mediaPreviewHeroTransitionDidCancel(
        _ operation: MediaPreviewHeroOperation
    )
}

/// Shared, render-server-driven hero transition for image and video previews.
/// Cleanup is committed before UIKit receives `completeTransition`, which
/// keeps the proxy-to-live-view handoff atomic during fast scroll/reopen paths.
@MainActor
final class MediaPreviewHeroAnimator: NSObject,
    UIViewControllerAnimatedTransitioning {
    private weak var participant: MediaPreviewHeroTransitionParticipant?
    private let operation: MediaPreviewHeroOperation
    private var activeCleanup: ((Bool) -> Void)?
    private var didReportOutcome = false
    private var didEndTransition = false

    private static let heroTimingFunction = CAMediaTimingFunction(
        controlPoints: 0.37, 0, 0.63, 1
    )

    init(
        operation: MediaPreviewHeroOperation,
        participant: MediaPreviewHeroTransitionParticipant
    ) {
        self.operation = operation
        self.participant = participant
        super.init()
    }

    func transitionDuration(
        using transitionContext: UIViewControllerContextTransitioning?
    ) -> TimeInterval {
        0.32
    }

    func animateTransition(
        using transitionContext: UIViewControllerContextTransitioning
    ) {
        guard let participant else {
            transitionContext.completeTransition(false)
            return
        }
        switch operation {
        case .presentation:
            animatePresentation(
                participant: participant,
                transitionContext: transitionContext
            )
        case .dismissal:
            animateDismissal(
                participant: participant,
                transitionContext: transitionContext
            )
        }
    }

    func animationEnded(_ transitionCompleted: Bool) {
        didEndTransition = true
        runActiveCleanup(completed: transitionCompleted)
        reportOutcome(completed: transitionCompleted)
    }

    private func animatePresentation(
        participant: MediaPreviewHeroTransitionParticipant,
        transitionContext: UIViewControllerContextTransitioning
    ) {
        guard let sourceController = transitionContext.viewController(forKey: .from),
              let destinationController = transitionContext.viewController(forKey: .to),
              let destinationView = transitionContext.view(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView
        destinationView.frame = transitionContext.finalFrame(for: destinationController)
        containerView.addSubview(destinationView)
        destinationView.layoutIfNeeded()

        guard let sourceView = participant.mediaPreviewStableSourceView(
            in: sourceController
        ),
        let image = sourceView.image,
        let sourceFrame = ImagePreviewTransitionGeometry.validSourceFrame(
            sourceView.convert(sourceView.bounds, to: containerView)
        ) else {
            animateCrossDissolve(
                appearingView: destinationView,
                disappearingView: nil,
                appearingViewWasInserted: true,
                transitionContext: transitionContext
            )
            return
        }

        let targetFrame = ImagePreviewTransitionGeometry.aspectFitFrame(
            imageSize: image.size,
            in: destinationView.frame
        )
        let sourceCornerRadius = sourceView.layer.cornerRadius
        guard let lease = ImagePreviewHeroSourceLease(
            sourceView: sourceView,
            image: image,
            sourceIdentity: participant.mediaPreviewHeroSourceIdentity,
            containerView: containerView,
            imageFrame: sourceFrame,
            cornerRadius: sourceCornerRadius
        ) else {
            animateCrossDissolve(
                appearingView: destinationView,
                disappearingView: nil,
                appearingViewWasInserted: true,
                transitionContext: transitionContext
            )
            return
        }

        let dimmingView = UIView(frame: containerView.bounds)
        dimmingView.backgroundColor = .black
        dimmingView.alpha = 0
        containerView.insertSubview(dimmingView, belowSubview: lease.proxyView)
        destinationView.alpha = 0
        let interactionGate = Self.makeInteractionGate(in: containerView)
        installActiveCleanup { completed in
            Self.removeInteractionGate(interactionGate)
            dimmingView.removeFromSuperview()
            lease.finish()
            destinationView.alpha = 1
            if completed == false {
                destinationView.removeFromSuperview()
            }
        }

        completeWithHeroAnimation(
            lease: lease,
            dimmingView: dimmingView,
            image: image,
            startFrame: sourceFrame,
            endFrame: targetFrame,
            startCornerRadius: sourceCornerRadius,
            endCornerRadius: 0,
            startDimmingOpacity: 0,
            endDimmingOpacity: 1,
            transitionContext: transitionContext
        )
    }

    private func animateDismissal(
        participant: MediaPreviewHeroTransitionParticipant,
        transitionContext: UIViewControllerContextTransitioning
    ) {
        guard let sourceController = transitionContext.viewController(forKey: .to),
              let dismissedView = transitionContext.view(forKey: .from) else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView
        let destinationView = transitionContext.view(forKey: .to)
        let destinationWasInserted: Bool
        if let destinationView, destinationView.superview == nil {
            destinationView.frame = transitionContext.finalFrame(for: sourceController)
            containerView.insertSubview(destinationView, belowSubview: dismissedView)
            destinationView.layoutIfNeeded()
            destinationWasInserted = true
        } else {
            destinationWasInserted = false
        }

        guard let sourceView = participant.mediaPreviewStableSourceView(
            in: sourceController
        ),
        let content = participant.mediaPreviewHeroDismissalContent(
            sourceView: sourceView,
            dismissedView: dismissedView,
            containerView: containerView
        ),
        let fullScreenFrame = ImagePreviewTransitionGeometry.validSourceFrame(
            content.frame
        ),
        let sourceFrame = ImagePreviewTransitionGeometry.validSourceFrame(
            sourceView.convert(sourceView.bounds, to: containerView)
        ) else {
            animateCrossDissolve(
                appearingView: destinationView,
                disappearingView: dismissedView,
                appearingViewWasInserted: destinationWasInserted,
                transitionContext: transitionContext
            )
            return
        }

        let sourceCornerRadius = sourceView.layer.cornerRadius
        guard let lease = ImagePreviewHeroSourceLease(
            sourceView: sourceView,
            image: content.image,
            sourceIdentity: participant.mediaPreviewHeroSourceIdentity,
            containerView: containerView,
            imageFrame: fullScreenFrame,
            cornerRadius: 0
        ) else {
            animateCrossDissolve(
                appearingView: destinationView,
                disappearingView: dismissedView,
                appearingViewWasInserted: destinationWasInserted,
                transitionContext: transitionContext
            )
            return
        }

        let dimmingView = UIView(frame: containerView.bounds)
        dimmingView.backgroundColor = .black
        dimmingView.alpha = 1
        containerView.insertSubview(dimmingView, belowSubview: lease.proxyView)
        containerView.insertSubview(dismissedView, belowSubview: lease.proxyView)
        dismissedView.alpha = 0
        let interactionGate = Self.makeInteractionGate(in: containerView)
        installActiveCleanup { completed in
            Self.removeInteractionGate(interactionGate)
            dimmingView.removeFromSuperview()
            lease.finish()
            dismissedView.alpha = 1
            if completed {
                dismissedView.removeFromSuperview()
            } else if destinationWasInserted {
                destinationView?.removeFromSuperview()
            }
        }

        completeWithHeroAnimation(
            lease: lease,
            dimmingView: dimmingView,
            image: content.image,
            startFrame: fullScreenFrame,
            endFrame: sourceFrame,
            startCornerRadius: 0,
            endCornerRadius: sourceCornerRadius,
            startDimmingOpacity: 1,
            endDimmingOpacity: 0,
            transitionContext: transitionContext
        )
    }

    private func completeWithHeroAnimation(
        lease: ImagePreviewHeroSourceLease,
        dimmingView: UIView,
        image: UIImage,
        startFrame: CGRect,
        endFrame: CGRect,
        startCornerRadius: CGFloat,
        endCornerRadius: CGFloat,
        startDimmingOpacity: Float,
        endDimmingOpacity: Float,
        transitionContext: UIViewControllerContextTransitioning
    ) {
        var didCompleteTransition = false
        let completeTransition = {
            guard didCompleteTransition == false,
                  self.didEndTransition == false else {
                return
            }
            didCompleteTransition = true
            let completed = transitionContext.transitionWasCancelled == false
            self.commitCleanupBeforeCompletion {
                self.runActiveCleanup(completed: completed)
            } completion: {
                self.reportOutcome(completed: completed)
                transitionContext.completeTransition(completed)
            }
        }

        runHeroAnimations(
            lease: lease,
            dimmingView: dimmingView,
            image: image,
            startFrame: startFrame,
            endFrame: endFrame,
            startCornerRadius: startCornerRadius,
            endCornerRadius: endCornerRadius,
            startDimmingOpacity: startDimmingOpacity,
            endDimmingOpacity: endDimmingOpacity,
            duration: transitionDuration(using: transitionContext),
            completion: completeTransition
        )
    }

    private func runHeroAnimations(
        lease: ImagePreviewHeroSourceLease,
        dimmingView: UIView,
        image: UIImage,
        startFrame: CGRect,
        endFrame: CGRect,
        startCornerRadius: CGFloat,
        endCornerRadius: CGFloat,
        startDimmingOpacity: Float,
        endDimmingOpacity: Float,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        let imageLayer = lease.proxyView.imageView.layer
        let startContentsRect = ImagePreviewTransitionGeometry.aspectFillContentsRect(
            imageSize: image.size,
            displaySize: startFrame.size
        )
        let endContentsRect = ImagePreviewTransitionGeometry.aspectFillContentsRect(
            imageSize: image.size,
            displaySize: endFrame.size
        )

        func heroAnimation(
            _ keyPath: String,
            from fromValue: NSValue,
            to toValue: NSValue
        ) -> CABasicAnimation {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = fromValue
            animation.toValue = toValue
            animation.duration = duration
            animation.timingFunction = Self.heroTimingFunction
            let maximumFramesPerSecond = Float(UIScreen.main.maximumFramesPerSecond)
            animation.preferredFrameRateRange = CAFrameRateRange(
                minimum: min(80, maximumFramesPerSecond),
                maximum: maximumFramesPerSecond,
                preferred: maximumFramesPerSecond
            )
            return animation
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(completion)

        lease.proxyView.render(
            frame: endFrame,
            imageSize: image.size,
            cornerRadius: endCornerRadius
        )
        dimmingView.layer.opacity = endDimmingOpacity

        imageLayer.add(
            heroAnimation(
                "bounds",
                from: NSValue(cgRect: CGRect(origin: .zero, size: startFrame.size)),
                to: NSValue(cgRect: CGRect(origin: .zero, size: endFrame.size))
            ),
            forKey: "hero-bounds"
        )
        imageLayer.add(
            heroAnimation(
                "position",
                from: NSValue(cgPoint: CGPoint(x: startFrame.midX, y: startFrame.midY)),
                to: NSValue(cgPoint: CGPoint(x: endFrame.midX, y: endFrame.midY))
            ),
            forKey: "hero-position"
        )
        imageLayer.add(
            heroAnimation(
                "cornerRadius",
                from: NSNumber(value: Double(startCornerRadius)),
                to: NSNumber(value: Double(endCornerRadius))
            ),
            forKey: "hero-corner-radius"
        )
        imageLayer.add(
            heroAnimation(
                "contentsRect",
                from: NSValue(cgRect: startContentsRect),
                to: NSValue(cgRect: endContentsRect)
            ),
            forKey: "hero-contents-rect"
        )
        dimmingView.layer.add(
            heroAnimation(
                "opacity",
                from: NSNumber(value: startDimmingOpacity),
                to: NSNumber(value: endDimmingOpacity)
            ),
            forKey: "hero-opacity"
        )

        CATransaction.commit()
    }

    private func animateCrossDissolve(
        appearingView: UIView?,
        disappearingView: UIView?,
        appearingViewWasInserted: Bool,
        transitionContext: UIViewControllerContextTransitioning
    ) {
        appearingView?.alpha = disappearingView == nil ? 0 : 1
        let interactionGate = Self.makeInteractionGate(
            in: transitionContext.containerView
        )
        installActiveCleanup { completed in
            Self.removeInteractionGate(interactionGate)
            appearingView?.alpha = 1
            if completed {
                disappearingView?.removeFromSuperview()
            } else {
                disappearingView?.alpha = 1
                if appearingViewWasInserted {
                    appearingView?.removeFromSuperview()
                }
            }
        }

        var didCompleteTransition = false
        let completeTransition = {
            guard didCompleteTransition == false,
                  self.didEndTransition == false else {
                return
            }
            didCompleteTransition = true
            let completed = transitionContext.transitionWasCancelled == false
            self.commitCleanupBeforeCompletion {
                self.runActiveCleanup(completed: completed)
            } completion: {
                self.reportOutcome(completed: completed)
                transitionContext.completeTransition(completed)
            }
        }

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext) * 0.7,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut],
            animations: {
                appearingView?.alpha = 1
                disappearingView?.alpha = 0
            },
            completion: { _ in
                completeTransition()
            }
        )
    }

    private func commitCleanupBeforeCompletion(
        _ cleanup: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(completion)
        cleanup()
        CATransaction.commit()
    }

    private func installActiveCleanup(_ cleanup: @escaping (Bool) -> Void) {
        runActiveCleanup(completed: false)
        activeCleanup = cleanup
    }

    private func runActiveCleanup(completed: Bool) {
        let cleanup = activeCleanup
        activeCleanup = nil
        cleanup?(completed)
    }

    private func reportOutcome(completed: Bool) {
        guard didReportOutcome == false else { return }
        didReportOutcome = true
        guard completed == false else { return }
        participant?.mediaPreviewHeroTransitionDidCancel(operation)
    }

    private static func makeInteractionGate(in containerView: UIView) -> UIView {
        let gate = UIView(frame: containerView.bounds)
        gate.backgroundColor = .clear
        gate.alpha = 1
        gate.isUserInteractionEnabled = true
        gate.accessibilityElementsHidden = true
        containerView.addSubview(gate)
        return gate
    }

    private static func removeInteractionGate(_ gate: UIView) {
        gate.removeFromSuperview()
    }
}
