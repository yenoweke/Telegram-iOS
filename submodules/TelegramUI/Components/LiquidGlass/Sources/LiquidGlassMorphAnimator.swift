import Foundation
import UIKit
import Display

public struct LiquidGlassMorphAnimatorConfiguration {
    public var sizeFactor: CGFloat = 0.3
    public var springStiffness: CGFloat = 0.12
    public var springDamping: CGFloat = 0.75
    public var squishFactor: CGFloat = 0.6
    public var lagFactor: CGFloat = 0.5
    public var morphRange: CGFloat = 0.5

    public init() {}
}

public final class LiquidGlassMorphAnimator {

    public var configuration = LiquidGlassMorphAnimatorConfiguration()
    public var onMorphScaleChanged: ((CGPoint) -> Void)?
    public private(set) var currentMorphScale: CGPoint = CGPoint(x: 1.0, y: 1.0)
    public private(set) var isAnimating: Bool = false

    private var targetMorphScale: CGPoint = CGPoint(x: 1.0, y: 1.0)
    private var laggedTargetMorphScale: CGPoint = CGPoint(x: 1.0, y: 1.0)
    private var springVelocity: CGPoint = .zero
    private var displayLink: SharedDisplayLinkDriver.Link?
    private var isDragging: Bool = false

    public init(configuration: LiquidGlassMorphAnimatorConfiguration = .init()) {
        self.configuration = configuration
    }

    deinit {
        forceStop()
    }

    public func start() {
        guard displayLink == nil else { return }
        isDragging = true

        displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .fps(60)) { [weak self] _ in
            self?.updateAnimation()
        }
        displayLink?.isPaused = false
        isAnimating = true
    }

    public func stop() {
        isDragging = false
        targetMorphScale = CGPoint(x: 1.0, y: 1.0)
    }

    public func forceStop() {
        displayLink?.isPaused = true
        displayLink?.invalidate()
        displayLink = nil
        isAnimating = false
        reset()
    }

    public func feedVelocity(_ velocity: CGPoint) {
        updateTargetMorphScale(from: velocity)
    }

    public func reset() {
        targetMorphScale = CGPoint(x: 1.0, y: 1.0)
        currentMorphScale = CGPoint(x: 1.0, y: 1.0)
        laggedTargetMorphScale = CGPoint(x: 1.0, y: 1.0)
        springVelocity = .zero
        onMorphScaleChanged?(currentMorphScale)
    }

    private func updateTargetMorphScale(from velocity: CGPoint) {
        let maxVelocity: CGFloat = 5000
        let clampedVelocity = CGPoint(
            x: max(-maxVelocity, min(maxVelocity, velocity.x)),
            y: max(-maxVelocity, min(maxVelocity, velocity.y))
        )

        let sizeFactor = configuration.sizeFactor
        let squishFactor = configuration.squishFactor
        let minScale = 1.0 - configuration.morphRange
        let maxScale = 1.0 + configuration.morphRange

        let stretchX = (clampedVelocity.x / 1000.0) * sizeFactor
        let stretchY = (clampedVelocity.y / 1000.0) * sizeFactor

        targetMorphScale = CGPoint(
            x: max(minScale, min(maxScale, 1.0 + stretchX - stretchY * squishFactor)),
            y: max(minScale, min(maxScale, 1.0 + stretchY - stretchX * squishFactor))
        )
    }

    private func updateAnimation() {
        let stiffness = configuration.springStiffness
        let damping = configuration.springDamping
        let lagFactor = configuration.lagFactor

        let smoothingRate = 1.0 - pow(lagFactor, 3.0)
        laggedTargetMorphScale = CGPoint(
            x: laggedTargetMorphScale.x + (targetMorphScale.x - laggedTargetMorphScale.x) * smoothingRate,
            y: laggedTargetMorphScale.y + (targetMorphScale.y - laggedTargetMorphScale.y) * smoothingRate
        )

        let forceX = (laggedTargetMorphScale.x - currentMorphScale.x) * stiffness
        springVelocity.x += forceX
        springVelocity.x *= damping
        currentMorphScale.x += springVelocity.x

        let forceY = (laggedTargetMorphScale.y - currentMorphScale.y) * stiffness
        springVelocity.y += forceY
        springVelocity.y *= damping
        currentMorphScale.y += springVelocity.y

        onMorphScaleChanged?(currentMorphScale)

        if !isDragging && shouldStopAnimation() {
            finalizeAnimation()
        }
    }

    private func shouldStopAnimation() -> Bool {
        let epsilon: CGFloat = 0.001

        let atRestTarget = targetMorphScale.x == 1.0 && targetMorphScale.y == 1.0
        let laggedSettled = abs(laggedTargetMorphScale.x - 1.0) < epsilon &&
                           abs(laggedTargetMorphScale.y - 1.0) < epsilon
        let reachedTarget = abs(currentMorphScale.x - 1.0) < epsilon &&
                           abs(currentMorphScale.y - 1.0) < epsilon
        let velocityNegligible = abs(springVelocity.x) < epsilon &&
                                 abs(springVelocity.y) < epsilon

        return atRestTarget && laggedSettled && reachedTarget && velocityNegligible
    }

    private func finalizeAnimation() {
        currentMorphScale = CGPoint(x: 1.0, y: 1.0)
        laggedTargetMorphScale = CGPoint(x: 1.0, y: 1.0)
        springVelocity = .zero
        onMorphScaleChanged?(currentMorphScale)

        displayLink?.isPaused = true
        displayLink?.invalidate()
        displayLink = nil
        isAnimating = false
    }
}
