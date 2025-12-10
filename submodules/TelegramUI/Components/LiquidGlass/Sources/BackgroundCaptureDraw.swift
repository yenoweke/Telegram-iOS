import Metal
import MetalKit
import UIKit

final class BackgroundCaptureDraw {

    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader

    private var imageRenderer: UIGraphicsImageRenderer?
    private var rendererSize: CGSize = .zero
    private var rendererScale: CGFloat = 0

    init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)
    }

    deinit {
        purge()
    }

    func captureTexture(
        from sourceView: UIView,
        region: CGRect,
        scale: CGFloat = 1.0,
        excludedViews: [UIView] = []
    ) -> MTLTexture? {
        let hiddenStates = excludedViews.map { $0.isHidden }
        excludedViews.forEach { $0.isHidden = true }

        defer {
            for (view, wasHidden) in zip(excludedViews, hiddenStates) {
                view.isHidden = wasHidden
            }
        }

        let screenScale = sourceView.window?.screen.scale ?? UIScreen.main.scale
        let effectiveScale = screenScale * scale

        let captureSize = CGSize(
            width: region.width,
            height: region.height
        )

        guard captureSize.width > 0 && captureSize.height > 0 else { return nil }

        if imageRenderer == nil || rendererSize != captureSize || rendererScale != effectiveScale {
            let format = UIGraphicsImageRendererFormat()
            format.scale = effectiveScale
            format.opaque = false
            format.preferredRange = .standard

            imageRenderer = UIGraphicsImageRenderer(size: captureSize, format: format)
            rendererSize = captureSize
            rendererScale = effectiveScale
        }

        guard let renderer = imageRenderer else { return nil }

        let image = renderer.image { ctx in
            ctx.cgContext.clear(CGRect(origin: .zero, size: captureSize))

            ctx.cgContext.translateBy(x: -region.origin.x, y: -region.origin.y)

            sourceView.drawHierarchy(
                in: sourceView.bounds,
                afterScreenUpdates: false
            )
        }

        guard let cgImage = image.cgImage else { return nil }

        do {
            return try textureLoader.newTexture(cgImage: cgImage, options: [
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .textureStorageMode: NSNumber(value: MTLStorageMode.shared.rawValue),
                .SRGB: false
            ])
        } catch {
            return nil
        }
    }

    func invalidateCache() {
    }

    func purge() {
        imageRenderer = nil
        rendererSize = .zero
        rendererScale = 0
    }
}
