import Metal
import Foundation

final class TexturePool {

    private let device: MTLDevice
    private var pool: [TextureKey: [MTLTexture]] = [:]
    private let lock = NSLock()
    private let maxTexturesPerKey = 6

    struct TextureKey: Hashable {
        let width: Int
        let height: Int
        let format: MTLPixelFormat

        func hash(into hasher: inout Hasher) {
            hasher.combine(width)
            hasher.combine(height)
            hasher.combine(format.rawValue)
        }
    }

    init(device: MTLDevice) {
        self.device = device
    }

    func acquire(width: Int, height: Int, format: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }

        let key = TextureKey(width: width, height: height, format: format)

        if var available = pool[key], !available.isEmpty {
            let texture = available.removeLast()
            pool[key] = available
            return texture
        }

        return createTexture(width: width, height: height, format: format)
    }

    func release(_ texture: MTLTexture) {
        lock.lock()
        defer { lock.unlock() }

        let key = TextureKey(
            width: texture.width,
            height: texture.height,
            format: texture.pixelFormat
        )

        guard (pool[key]?.count ?? 0) < maxTexturesPerKey else {
            return
        }

        pool[key, default: []].append(texture)
    }

    func purge() {
        lock.lock()
        defer { lock.unlock() }

        pool.removeAll()
    }

    func cleanupUnusedTextures() {
        lock.lock()
        defer { lock.unlock() }

        for key in pool.keys {
            if let textures = pool[key], textures.count > 2 {
                pool[key] = Array(textures.suffix(2))
            }
        }
    }

    var stats: (textureCount: Int, uniqueSizes: Int) {
        lock.lock()
        defer { lock.unlock() }

        let count = pool.values.reduce(0) { $0 + $1.count }
        return (count, pool.count)
    }

    private func createTexture(width: Int, height: Int, format: MTLPixelFormat) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )

        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]

        return device.makeTexture(descriptor: descriptor)
    }
}
