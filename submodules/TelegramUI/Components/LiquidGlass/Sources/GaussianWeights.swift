import Foundation
import Metal

final class GaussianWeights {

    private let device: MTLDevice
    private var cachedWeightsBuffer: MTLBuffer?
    private var cachedRadius: Int = -1
    private var cachedSigma: Float = -1

    init(device: MTLDevice) {
        self.device = device
    }

    func weightsBuffer(radius: Int, sigma: Float) -> MTLBuffer? {
        if radius == cachedRadius && abs(sigma - cachedSigma) < 0.001 {
            return cachedWeightsBuffer
        }

        let weights = calculateWeights(radius: radius, sigma: sigma)

        cachedWeightsBuffer = device.makeBuffer(
            bytes: weights,
            length: MemoryLayout<Float>.stride * weights.count,
            options: .storageModeShared
        )

        cachedRadius = radius
        cachedSigma = sigma

        return cachedWeightsBuffer
    }

    func calculateWeights(radius: Int, sigma: Float) -> [Float] {
        guard radius > 0 && sigma > 0 else {
            return [1.0]
        }

        var weights = [Float](repeating: 0, count: radius + 1)
        let sigma2 = 2.0 * sigma * sigma

        var sum: Float = 0
        for i in 0...radius {
            let x = Float(i)
            let weight = exp(-(x * x) / sigma2)
            weights[i] = weight

            if i == 0 {
                sum += weight
            } else {
                sum += weight * 2
            }
        }

        for i in 0...radius {
            weights[i] /= sum
        }

        return weights
    }

    func invalidateCache() {
        cachedWeightsBuffer = nil
        cachedRadius = -1
        cachedSigma = -1
    }
}
