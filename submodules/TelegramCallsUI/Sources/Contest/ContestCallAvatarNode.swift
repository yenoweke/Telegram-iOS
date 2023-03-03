import Foundation
import UIKit
import Display
import AsyncDisplayKit
import AvatarNode
import SwiftSignalKit
import TelegramCore
import AccountContext
import AudioBlob

final class ContestCallAvatarNode: ASDisplayNode {
    private var audioLevelView: VoiceBlobView?
    private let imageNode: ASImageNode
//    private var imageMaskLayer: CAShapeLayer
    private let avatarFont: UIFont

    private var imageMaskBlobPath: CGPath?
    private var imageMaskCirclePath: CGPath?

    private var validLayout: CGSize?
    private var size: CGSize
    
    private var disposable: Disposable?
    
    init(size: CGSize, avatarFont: UIFont) {
        self.size = size
        self.avatarFont = avatarFont
//        self.imageMaskLayer = CAShapeLayer()
        self.imageNode = ASImageNode()
        super.init()
        self.addSubnode(self.imageNode)
//        self.imageMaskLayer.fillColor = UIColor.black.cgColor
        self.imageNode.clipsToBounds = true
        
        // removed, not sure that image is blobed
//        self.prepareBlobMask()
//        self.imageNode.layer.mask = self.imageMaskLayer
    }
    
    func setPeer(context: AccountContext, peer: EnginePeer?, synchronousLoad: Bool, placeholderColor: UIColor) {
        if let peer = peer {
            if let representation = peer.smallProfileImage, let signal = peerAvatarImage(account: context.account, peerReference: PeerReference(peer._asPeer()), authorOfMessage: nil, representation: representation, displayDimensions: size, synchronousLoad: synchronousLoad) {
                let image = generateImage(size, rotatedContext: { size, context in
                    context.clear(CGRect(origin: CGPoint(), size: size))
                    context.setFillColor(UIColor.lightGray.cgColor)
                    context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
                })!
                self.updateImage(image: image)

                let disposable = (signal
                |> deliverOnMainQueue).start(next: { [weak self] imageVersions in
                    guard let strongSelf = self else {
                        return
                    }
                    let image = imageVersions?.0
                    if let image = image {
                        strongSelf.updateImage(image: image)
                    }
                })
                self.disposable = disposable
            } else {
                let image = generateImage(size, rotatedContext: { size, context in
                    context.clear(CGRect(origin: CGPoint(), size: size))
                    drawPeerAvatarLetters(context: context, size: size, font: avatarFont, letters: peer.displayLetters, peerId: peer.id)
                })!
                self.updateImage(image: image)
            }
        } else {
            let image = generateImage(size, rotatedContext: { size, context in
                context.clear(CGRect(origin: CGPoint(), size: size))
                context.setFillColor(placeholderColor.cgColor)
                context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
            })!
            self.updateImage(image: image)
        }
    }
    
    private func updateImage(image: UIImage) {
        self.imageNode.image = image
    }
    
    deinit {
        self.disposable?.dispose()
    }
    
    func updateLayout(size: CGSize) {
        // TODO: regenerate image if changed and update audioLevelView
        if self.validLayout == size {
            return
        }
        self.validLayout = size
        self.imageNode.frame = CGRect(origin: CGPoint(), size: size)
//        self.imageMaskLayer.frame = CGRect(origin: CGPoint(x: size.width / 2.0, y: size.height / 2.0), size: size)
//        self.imageMaskCirclePath = UIBezierPath(roundedRect: self.imageNode.bounds, cornerRadius: size.width / 2.0).cgPath
//        self.prepareBlobMask()
    }
    
    func stopAnimating() {
        self.audioLevelView?.stopAnimating(duration: 2.0)
        self.changeImageMask(circle: true)
    }
    
    func animateInAndOut(completion: @escaping () -> Void) {
        let transition: ContainedViewLayoutTransition = .animated(duration: 0.2, curve: .easeInOut)

        if let audioLevelView = self.audioLevelView {
            transition.updateTransformScale(layer: audioLevelView.layer, scale: 1.4)
        }

        transition.updateTransformScale(layer: self.imageNode.layer, scale: 1.12) { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
            transition.updateTransformScale(layer: strongSelf.imageNode.layer, scale: 1.0, completion: { _ in
                completion()
            })
            if let audioLevelView = strongSelf.audioLevelView {
                transition.updateTransformScale(layer: audioLevelView.layer, scale: 1.0)
            }
        }
    }
    
    func updateAudioLevel(color: UIColor, value: Float) {
        if self.audioLevelView == nil, value > 0.0 {
            let blobFrame = self.imageNode.bounds.insetBy(dx: -30.0, dy: -30.0)
            
            let audioLevelView = VoiceBlobView(
                frame: blobFrame,
                maxLevel: 0.7,
                smallBlobRange: (0, 0),
                mediumBlobRange: (0.73, 0.9),
                bigBlobRange: (0.84, 0.95)
            )
            
            audioLevelView.setColor(color)
            self.audioLevelView = audioLevelView
            self.view.insertSubview(audioLevelView, at: 0)
        }
        
        if let audioLevelView = self.audioLevelView {
            audioLevelView.updateLevel(CGFloat(value))
            
            let audioLevelScale: CGFloat
            if value > 0.0 {
                audioLevelView.startAnimating()
                audioLevelScale = 1.0
                self.changeImageMask(circle: false)
            } else {
                audioLevelView.stopAnimating(duration: 0.5)
                audioLevelScale = 0.01
                self.changeImageMask(circle: true)
            }
            
            let transition: ContainedViewLayoutTransition = .animated(duration: 0.2, curve: .easeInOut)
            transition.updateSublayerTransformScale(layer: audioLevelView.layer, scale: CGPoint(x: audioLevelScale, y: audioLevelScale), beginWithCurrentState: true)
        }
    }
    
    private var isCirclePath: Bool = true
    
    private func changeImageMask(circle: Bool) {
//        if isCirclePath == circle {
//            return
//        }
//        self.isCirclePath = circle
//
//        let fromPath = imageMaskLayer.path
//        let toPath: CGPath
//        if circle, let imageMaskCirclePath = self.imageMaskCirclePath {
//            toPath = imageMaskCirclePath
//        } else if let imageMaskBlobPath = self.imageMaskBlobPath {
//            toPath = imageMaskBlobPath
//        } else {
//            return
//        }
//        self.imageMaskLayer.path = toPath
//        self.imageMaskLayer.animate(from: fromPath, to: toPath, keyPath: "path", timingFunction: CAMediaTimingFunctionName.linear.rawValue, duration: 0.3, removeOnCompletion: false)
    }
    
    private func prepareBlobMask() {
        let (imageNodeBlobPoints, smoothness) = generateBlob(for: self.size)
        let imageNodeBlobPath = UIBezierPath.smoothCurve(through: imageNodeBlobPoints, length: self.size.width, smoothness: smoothness).cgPath
        self.imageMaskBlobPath = imageNodeBlobPath
    }
}

private func generateBlob(for size: CGSize) -> ([CGPoint], CGFloat) {
    let minRandomness: CGFloat = 0.1
    let maxRandomness: CGFloat = 0.2
    let speedLevel: CGFloat = 1.0
    let pointsCount: Int = 8
    let randomness = minRandomness + (maxRandomness - minRandomness) * speedLevel
    
    let angle = (CGFloat.pi * 2) / CGFloat(pointsCount)
    let smoothness = ((4 / 3) * tan(angle / 4)) / sin(angle / 2) / 2
    
    return (blob(pointsCount: pointsCount, randomness: randomness)
        .map {
            return CGPoint(
                x: $0.x * CGFloat(size.width),
                y: $0.y * CGFloat(size.height)
            )
        }, smoothness)
}

private func blob(pointsCount: Int, randomness: CGFloat) -> [CGPoint] {
    let angle = (CGFloat.pi * 2) / CGFloat(pointsCount)
    
    let rgen = { () -> CGFloat in
        let accuracy: UInt32 = 1000
        let random = arc4random_uniform(accuracy)
        return CGFloat(random) / CGFloat(accuracy)
    }
    let rangeStart: CGFloat = 1 / (1 + randomness / 10)
    
    let startAngle = angle * CGFloat(arc4random_uniform(100)) / CGFloat(100)
    
    let points = (0 ..< pointsCount).map { i -> CGPoint in
        let randPointOffset = (rangeStart + CGFloat(rgen()) * (1 - rangeStart)) / 2
        let angleRandomness: CGFloat = angle * 0.1
        let randAngle = angle + angle * ((angleRandomness * CGFloat(arc4random_uniform(100)) / CGFloat(100)) - angleRandomness * 0.5)
        let pointX = sin(startAngle + CGFloat(i) * randAngle)
        let pointY = cos(startAngle + CGFloat(i) * randAngle)
        return CGPoint(
            x: pointX * randPointOffset,
            y: pointY * randPointOffset
        )
    }
    
    return points
}
