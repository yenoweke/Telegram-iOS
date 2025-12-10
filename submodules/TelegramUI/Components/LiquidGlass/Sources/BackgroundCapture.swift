import Metal
import MetalKit
import UIKit
import IOSurface
import CoreVideo

struct CaptureResult {
    let texture: MTLTexture
    let surface: IOSurface
}

private final class IOSurfacePool {
    private var pool: [IOSurfaceKey: [IOSurface]] = [:]
    private let lock = NSLock()
    private let maxSurfacesPerKey = 4

    struct IOSurfaceKey: Hashable {
        let width: Int
        let height: Int
    }

    func acquire(width: Int, height: Int) -> IOSurface? {
        lock.lock()
        defer { lock.unlock() }

        let key = IOSurfaceKey(width: width, height: height)

        if var available = pool[key], !available.isEmpty {
            let surface = available.removeLast()
            pool[key] = available
            return surface
        }

        return createSurface(width: width, height: height)
    }

    func release(_ surface: IOSurface) {
        lock.lock()
        defer { lock.unlock() }

        let key = IOSurfaceKey(
            width: IOSurfaceGetWidth(surface),
            height: IOSurfaceGetHeight(surface)
        )

        guard (pool[key]?.count ?? 0) < maxSurfacesPerKey else {
            return
        }

        pool[key, default: []].append(surface)
    }

    func purge() {
        lock.lock()
        defer { lock.unlock() }
        pool.removeAll()
    }

    private func createSurface(width: Int, height: Int) -> IOSurface? {
        let bytesPerRow = ((width * 4) + 15) & ~15
        let properties: [IOSurfacePropertyKey: Any] = [
            .width: width,
            .height: height,
            .bytesPerElement: 4,
            .bytesPerRow: bytesPerRow,
            .allocSize: bytesPerRow * height,
            .pixelFormat: kCVPixelFormatType_32BGRA
        ]
        return IOSurfaceCreate(properties as CFDictionary)
    }
}

final class BackgroundCapture {

    private let device: MTLDevice
    private let surfacePool = IOSurfacePool()

    init(device: MTLDevice) {
        self.device = device
    }

    deinit {
        purge()
    }

    func captureTexture(
        from sourceView: UIView,
        region: CGRect,
        scale: CGFloat = 1.0,
        excludedViews: [UIView] = []
    ) -> CaptureResult? {
        let hiddenStates = excludedViews.map { $0.isHidden }
        excludedViews.forEach { $0.isHidden = true }

        defer {
            for (view, wasHidden) in zip(excludedViews, hiddenStates) {
                view.isHidden = wasHidden
            }
        }

        let screenScale = sourceView.window?.screen.scale ?? UIScreen.main.scale
        let effectiveScale = screenScale * scale

        guard region.width > 0 && region.height > 0 else { return nil }

        let pixelWidth = Int(ceil(region.width * effectiveScale))
        let pixelHeight = Int(ceil(region.height * effectiveScale))

        guard pixelWidth > 0 && pixelHeight > 0 else { return nil }

        guard let surface = surfacePool.acquire(width: pixelWidth, height: pixelHeight) else {
            return nil
        }

        let lockResult = IOSurfaceLock(surface, [], nil)
        guard lockResult == 0 else {
            surfacePool.release(surface)
            return nil
        }

        defer {
            IOSurfaceUnlock(surface, [], nil)
        }

        let bytesPerRow = IOSurfaceGetBytesPerRow(surface)
        let baseAddress = IOSurfaceGetBaseAddress(surface)

        guard let context = CGContext(
            data: baseAddress,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            surfacePool.release(surface)
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: effectiveScale, y: -effectiveScale)
        context.translateBy(x: -region.origin.x, y: -region.origin.y)

        sourceView.layer.render(in: context)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: pixelWidth,
            height: pixelHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(
            descriptor: descriptor,
            iosurface: surface,
            plane: 0
        ) else {
            surfacePool.release(surface)
            return nil
        }

        return CaptureResult(texture: texture, surface: surface)
    }

    func releaseSurface(_ surface: IOSurface) {
        surfacePool.release(surface)
    }

    func invalidateCache() {
    }

    func purge() {
        surfacePool.purge()
    }
}
