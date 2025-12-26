import UIKit
import QuartzCore
import Display

public protocol LiquidGlassMorphingGestureDelegate: AnyObject {

    func morphingGestureDidBegin(_ handler: LiquidGlassMorphingGestureHandler)
    func morphingGesture(
        _ handler: LiquidGlassMorphingGestureHandler,
        positionForTranslation translation: CGPoint,
        currentCenter: CGPoint,
        in bounds: CGRect
    ) -> CGPoint?
    func morphingGestureDidEnd(_ handler: LiquidGlassMorphingGestureHandler, velocity: CGPoint)
}

public extension LiquidGlassMorphingGestureDelegate {
    func morphingGestureDidBegin(_ handler: LiquidGlassMorphingGestureHandler) {}
    func morphingGestureDidEnd(_ handler: LiquidGlassMorphingGestureHandler, velocity: CGPoint) {}
}

public final class LiquidGlassMorphingGestureHandler {
    public weak var delegate: LiquidGlassMorphingGestureDelegate?
    public var isMorphingEnabled: Bool = true
    public private(set) var isDragging: Bool = false
    public var targetView: LiquidGlassView? {
        _targetView
    }
    private weak var _targetView: LiquidGlassView?
    private var panGestureRecognizer: UIPanGestureRecognizer?
    private var lastDragPosition: CGPoint = .zero
    private var lastDragTime: CFTimeInterval = 0

    private var morphAnimator: LiquidGlassMorphAnimator?
    public init(targetView: LiquidGlassView) {
        self._targetView = targetView
        setupMorphAnimator()
        setupGestureRecognizer()
    }

    deinit {
        morphAnimator?.forceStop()
        removeGestureRecognizer()
    }

    private func setupMorphAnimator() {
        guard let config = _targetView?.configuration else { return }

        var animatorConfig = LiquidGlassMorphAnimatorConfiguration()
        animatorConfig.sizeFactor = config.morphSizeFactor
        animatorConfig.springStiffness = config.morphSpringStiffness
        animatorConfig.springDamping = config.morphSpringDamping
        animatorConfig.squishFactor = config.morphSquishFactor
        animatorConfig.lagFactor = config.morphLagFactor

        let animator = LiquidGlassMorphAnimator(configuration: animatorConfig)
        animator.onMorphScaleChanged = { [weak self] scale in
            self?._targetView?.setMorphScale(scale)
        }
        self.morphAnimator = animator
    }

    private func setupGestureRecognizer() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        _targetView?.addGestureRecognizer(pan)
        panGestureRecognizer = pan
    }

    private func removeGestureRecognizer() {
        if let gesture = panGestureRecognizer, let view = gesture.view {
            view.removeGestureRecognizer(gesture)
        }
        panGestureRecognizer = nil
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let targetView = _targetView,
              let superview = targetView.superview else { return }

        let translation = gesture.translation(in: superview)
        let currentTime = CACurrentMediaTime()

        switch gesture.state {
        case .began:
            handleGestureBegan(gesture: gesture, in: superview, at: currentTime)

        case .changed:
            handleGestureChanged(
                gesture: gesture,
                translation: translation,
                targetView: targetView,
                superview: superview,
                currentTime: currentTime
            )

        case .ended, .cancelled:
            handleGestureEnded(gesture: gesture, in: superview)

        default:
            break
        }

        gesture.setTranslation(.zero, in: superview)
    }

    private func handleGestureBegan(gesture: UIPanGestureRecognizer, in superview: UIView, at currentTime: CFTimeInterval) {
        lastDragPosition = gesture.location(in: superview)
        lastDragTime = currentTime
        isDragging = true
        morphAnimator?.start()
        delegate?.morphingGestureDidBegin(self)
    }

    private func handleGestureChanged(
        gesture: UIPanGestureRecognizer,
        translation: CGPoint,
        targetView: LiquidGlassView,
        superview: UIView,
        currentTime: CFTimeInterval
    ) {
        let currentPosition = gesture.location(in: superview)
        let dt = currentTime - lastDragTime

        if dt > 0.001 && isMorphingEnabled {
            let velocity = CGPoint(
                x: (currentPosition.x - lastDragPosition.x) / dt,
                y: (currentPosition.y - lastDragPosition.y) / dt
            )
            morphAnimator?.feedVelocity(velocity)
        }

        lastDragPosition = currentPosition
        lastDragTime = currentTime

        if let newCenter = delegate?.morphingGesture(
            self,
            positionForTranslation: translation,
            currentCenter: targetView.center,
            in: superview.bounds
        ) {
            targetView.center = newCenter
        }
    }

    private func handleGestureEnded(gesture: UIPanGestureRecognizer, in superview: UIView) {
        isDragging = false
        morphAnimator?.stop()
        delegate?.morphingGestureDidEnd(self, velocity: gesture.velocity(in: superview))
    }
    public func resetMorphScale() {
        morphAnimator?.reset()
    }

    public func detach() {
        morphAnimator?.forceStop()
        removeGestureRecognizer()
        _targetView = nil
    }
}
