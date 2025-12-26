import UIKit

public enum CaptureMethod {
    case ioSurface
    case drawHierarchy
}

public struct LiquidGlassConfiguration {

    public var blurRadius: CGFloat = 1
    public var sigma: CGFloat?
    public var cornerRadius: CGFloat = 16
    public var shapePadding: CGPoint = .zero
    public var quality: QualityLevel?
    public var opacity: CGFloat = 1.0
    public var capturePadding: CGPoint?
    public var captureMethod: CaptureMethod = .ioSurface

    public var refThickness: CGFloat = 25.0
    public var refFactor: CGFloat = 1.42
    public var refDispersion: CGFloat = 3.5

    public var useReflection: Bool = false

    public var tint: UIColor = .clear

    public var fresnelRange: CGFloat = 50.0
    public var fresnelFactor: CGFloat = 1.0
    public var fresnelHardness: CGFloat = 10.0

    public var glareRange: CGFloat = 500.0
    public var glareFactor: CGFloat = 1.0
    public var glareHardness: CGFloat = 0.5
    public var glareConvergence: CGFloat = 0.8
    public var glareAngle: CGFloat = .pi / 4
    public var glareOppositeFactor: CGFloat = 0.667
    public var glareFarsideColor: UIColor = UIColor(white: 0.0, alpha: 0.7)
    public var glareNearsideColor: UIColor = UIColor(white: 1.0, alpha: 0.7)

    public var morphScale: CGPoint = CGPoint(x: 1.0, y: 1.0)
    public var morphSizeFactor: CGFloat = 0.2
    public var morphSpringStiffness: CGFloat = 0.08
    public var morphSpringDamping: CGFloat = 0.8
    public var morphSquishFactor: CGFloat = 0.8
    public var morphLagFactor: CGFloat = 0.85

    public init() {}

    public var effectiveSigma: CGFloat {
        sigma ?? (blurRadius / 3.0)
    }

    public var effectiveCapturePadding: CGPoint {
        let defaultPadding = blurRadius * 1.5
        return CGPoint(
            x: (capturePadding?.x ?? defaultPadding) + shapePadding.x,
            y: (capturePadding?.y ?? defaultPadding) + shapePadding.y
        )
    }

    public func effectiveBlurRadius(for quality: QualityLevel) -> Int {
        min(Int(blurRadius), quality.maxBlurRadius)
    }
}
