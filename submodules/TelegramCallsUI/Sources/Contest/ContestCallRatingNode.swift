import Foundation
import UIKit
import SwiftSignalKit
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramVoip
import AccountContext
import AppBundle
import ComponentFlow
import AnimatedStickerNode
import TelegramAnimatedStickerNode

private let buttonCornerRadius: CGFloat = 14.0
private let buttonFont = Font.semibold(17.0)
private let durationForCancelAnimation: TimeInterval = 8.0
private let actionButtonHeight: CGFloat = 56.0
private let actionButtonFinalHeight: CGFloat = 50.0

private final class CountdownButtonNode: HighlightTrackingButtonNode {
    private let underlayTextNode: ASTextNode
    private let underlayContainerNode: ASDisplayNode
    private let underlayActionButtonMaskLayer = CAShapeLayer()
    private let filledImageNode: ASImageNode
    private let filledActionButtonMaskLayer = CAShapeLayer()
    private let text: String
    
    private var lastImageSize: CGSize?
    private var lastImage: UIImage?
    private var validSize: CGSize?

    init(text: String) {
        self.text = text
        self.filledImageNode = ASImageNode()
        self.underlayTextNode = ASTextNode()
        self.underlayContainerNode = ASDisplayNode()
        self.underlayContainerNode.isHidden = true

        super.init()
        self.setup()
        
        let overlay = ASDisplayNode()
        overlay.isUserInteractionEnabled = false
        overlay.alpha = 0.0
        overlay.backgroundColor = .white.withAlphaComponent(0.2)
        self.addSubnode(overlay)
        self.highligthedChanged = { [weak overlay, weak self] highlighted in
            guard let overlay = overlay, let strongSelf = self else {
                return
            }
            if highlighted {
                overlay.alpha = 1.0
                overlay.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                let transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .spring)
                transition.updateTransformScale (node: strongSelf, scale: 0.9)
            } else {
                overlay.alpha = 0.0
                overlay.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
                let transition: ContainedViewLayoutTransition = .animated(duration: 0.5, curve: .spring)
                transition.updateTransformScale(node: strongSelf, scale: 1.0)
            }
        }
    }
    
    func startAnimation() {
        let transition: ContainedViewLayoutTransition = .animated(duration: durationForCancelAnimation, curve: .linear)
        
        self.underlayContainerNode.isHidden = false
        let underLayer = CAShapeLayer()
        underLayer.fillColor = UIColor.black.cgColor
        underLayer.frame = self.underlayContainerNode.bounds
        underLayer.path = UIBezierPath(rect: self.underlayContainerNode.bounds).cgPath
        self.underlayContainerNode.layer.mask = underLayer
        
        let underEndPosition = underLayer.position
        let underStartPosition = CGPoint(x: underLayer.position.x - underLayer.frame.width, y: underLayer.position.y)
        transition.animatePosition(layer: underLayer, from: underStartPosition, to: underEndPosition, removeOnCompletion: false)
        
        let filledLayer = CAShapeLayer()
        filledLayer.fillColor = UIColor.black.cgColor
        filledLayer.frame = self.filledImageNode.bounds
        filledLayer.path = UIBezierPath(rect: self.filledImageNode.bounds).cgPath
        self.filledImageNode.layer.mask = filledLayer

        let filledtartPosition = filledLayer.position
        let filledEndPostition = CGPoint(x: filledLayer.position.x + filledLayer.frame.width, y: filledLayer.position.y)
        transition.animatePosition(layer: filledLayer, from: filledtartPosition, to: filledEndPostition, removeOnCompletion: false)
    }
    
    private func setup() {
        self.underlayContainerNode.addSubnode(self.underlayTextNode)
        self.addSubnode(self.underlayContainerNode)
        self.addSubnode(self.filledImageNode)
        
        self.filledActionButtonMaskLayer.fillColor = UIColor.black.cgColor
        self.underlayActionButtonMaskLayer.fillColor = UIColor.black.cgColor
        
        self.underlayTextNode.attributedText = NSAttributedString(string: self.text, font: buttonFont, textColor: .white, paragraphAlignment: .center)
        self.underlayContainerNode.backgroundColor = .white.withAlphaComponent(0.25)
    }
    
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        if let validSize = self.validSize, validSize == size {
            return
        }
        
        self.validSize = size
        
        self.filledImageNode.image = makeActionTextImageIfNeeded(size: size)
        transition.updateFrame(node: self.filledImageNode, frame: CGRect(origin: .zero, size: size))
        transition.updateFrame(node: self.underlayContainerNode, frame: CGRect(origin: .zero, size: size))
        
        let underTextSize = self.underlayTextNode.measure(CGSize(width: size.width, height: size.height))
        let underTextOrigin = CGPoint(x: floor((size.width - underTextSize.width) / 2.0), y: floor(size.height - underTextSize.height) / 2.0)
        transition.updateFrame(node: self.underlayTextNode, frame: CGRect(origin: underTextOrigin, size: underTextSize))
    }
    
    private func makeActionTextImageIfNeeded(size: CGSize) -> UIImage? {
        if self.lastImageSize == size, let lastImage = self.lastImage {
            return lastImage
        }
        
        self.lastImageSize = size
        self.lastImage = textTransparentImage(size: size, text: self.text)
        return self.lastImage
    }
}

final class ContestCallRatingNode: ASDisplayNode {
    private let strings: PresentationStrings
    private let apply: (Int) -> Void
    private let dismiss: () -> Void
    
    var rating: Int?
    
    private let contentNode: ASDisplayNode
    private let contentEffectView: UIVisualEffectView
    private let titleNode: ASTextNode
    private let subtitleNode: ASTextNode
    private var starContainerNode: ASDisplayNode
    private let starNodes: [ASButtonNode]
    private var ratingDidApply = false
    private let countdownButtonNode: CountdownButtonNode
    
    private var validLayout: CGSize?
    private var lastFinalSize: CGSize?
    private var animatedInProgress = false
    private var animationFinished = false
    private let hapticFeedback = HapticFeedback()
    
    init(strings: PresentationStrings, light: Bool, dismiss: @escaping () -> Void, apply: @escaping (Int) -> Void) {
        self.strings = strings
        self.apply = apply
        self.dismiss = dismiss
        
        self.contentNode = ASDisplayNode()
        self.contentNode.clipsToBounds = true
        self.contentNode.cornerRadius = 20.0
    
        if #available(iOS 13.0, *) {
            self.contentNode.layer.cornerCurve = .continuous
            self.contentEffectView = UIVisualEffectView(effect: UIBlurEffect(style: light ? .systemThinMaterialLight : .systemThinMaterialDark))
        } else {
            self.contentEffectView = UIVisualEffectView(effect: UIBlurEffect(style: light ? .light : .dark))
        }
        self.contentEffectView.alpha = 0.25
        
        self.titleNode = ASTextNode()

        self.subtitleNode = ASTextNode()
        self.subtitleNode.maximumNumberOfLines = 3
        
        self.starContainerNode = ASDisplayNode()
        
        var starNodes: [ASButtonNode] = []
        for _ in 0 ..< 5 {
            starNodes.append(ASButtonNode())
        }
        self.starNodes = starNodes
        
        self.countdownButtonNode = CountdownButtonNode(text: strings.Common_Close)

        super.init()
        
        self.contentNode.view.addSubview(self.contentEffectView)
        self.contentNode.addSubnode(self.titleNode)
        self.contentNode.addSubnode(self.subtitleNode)
        self.contentNode.addSubnode(self.starContainerNode)
        
        for node in self.starNodes {
            node.addTarget(self, action: #selector(self.starPressed(_:)), forControlEvents: .touchDown)
            node.addTarget(self, action: #selector(self.starReleased(_:)), forControlEvents: .touchUpInside)
            self.starContainerNode.addSubnode(node)
        }
        self.countdownButtonNode.addTarget(self, action: #selector(self.actionPressed(_:)), forControlEvents: .touchUpInside)
        self.addSubnode(self.contentNode)
        self.addSubnode(self.countdownButtonNode)
        
        self.titleNode.attributedText = NSAttributedString(string: self.strings.Calls_ContestRatingTitle, font: Font.semibold(16.0), textColor: .white, paragraphAlignment: .center)
        
        self.subtitleNode.attributedText = NSAttributedString(string: self.strings.Calls_ContestRatingSubtitle, font: Font.regular(16.0), textColor: .white, paragraphAlignment: .center)

        for node in self.starNodes {
            node.setImage(generateTintedImage(image: UIImage(bundleImageName: "Call/ContestStar"), color: .white), for: [])
            let highlighted = generateTintedImage(image: UIImage(bundleImageName: "Call/ContestStarHighlighted"), color: .white)
            node.setImage(highlighted, for: [.selected])
            node.setImage(highlighted, for: [.selected, .highlighted])
        }
        self.starContainerNode.view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:))))
        
        self.contentNode.alpha = 0.0
        self.countdownButtonNode.alpha = 0.0
        self.countdownButtonNode.clipsToBounds = true
    }

    func animateIn(buttonFrom: CGRect?, buttonSnapshot: UIView?, transition: ContainedViewLayoutTransition) {
        if self.animatedInProgress {
            return
        }
        self.animatedInProgress = true
        guard let buttonFrom = buttonFrom, let buttonSnapshot = buttonSnapshot else {
            transition.updateAlpha(node: self.contentNode, alpha: 1.0)
            transition.updateAlpha(layer: self.countdownButtonNode.layer, alpha: 1.0, completion: { [weak self] _ in
                self?.countdownButtonNode.startAnimation()
                self?.animatedInProgress = false
            })
            transition.animateTransformScale(node: self.contentNode, from: 0.8)
            transition.animateTransformScale(node: self.countdownButtonNode, from: 0.8)
            return
        }
    
        buttonSnapshot.frame = buttonFrom
        self.view.insertSubview(buttonSnapshot, belowSubview: self.countdownButtonNode.view)

        let backColor = UIColor(rgb: 0xff3b30)
        let expandingView = UIView()
        expandingView.backgroundColor = backColor
        expandingView.frame = buttonFrom
        expandingView.layer.cornerRadius = buttonFrom.height / 2.0
        self.view.insertSubview(expandingView, belowSubview: buttonSnapshot)

        transition.updateFrame(view: expandingView, frame: self.countdownButtonNode.frame)
        transition.updateCornerRadius(layer: expandingView.layer, cornerRadius: self.countdownButtonNode.cornerRadius)
        expandingView.layer.animate(from: backColor, to: UIColor.white.cgColor, keyPath: "backgroundColor", timingFunction: CAMediaTimingFunctionName.easeIn.rawValue, duration: 0.3)
        transition.updateAlpha(layer: expandingView.layer, alpha: 0.0, completion: { [weak expandingView] _ in
            expandingView?.removeFromSuperview()
        })
        transition.updateAlpha(layer: buttonSnapshot.layer, alpha: 0.0, completion: { [weak buttonSnapshot] _ in
            buttonSnapshot?.removeFromSuperview()
        })
    
        transition.animateTransformScale(node: self.contentNode, from: 0.7)
        transition.updateAlpha(node: self.contentNode, alpha: 1.0)
        transition.updateAlpha(node: self.countdownButtonNode, alpha: 1.0, completion: { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
            strongSelf.animatedInProgress = false
            strongSelf.animationFinished = true
            if let validLayout = strongSelf.validLayout {
                _ = strongSelf.updateLayout(size: validLayout, transition: .immediate)
                strongSelf.countdownButtonNode.layer.mask = nil
            }
            strongSelf.countdownButtonNode.startAnimation()
        })

        let fillLayer = CAShapeLayer()
        fillLayer.fillColor = UIColor.black.cgColor
        let fromRect = self.view.convert(buttonFrom, to: self.countdownButtonNode.view)

        let diffX = fromRect.maxX - self.countdownButtonNode.frame.maxX
        let fromPath = UIBezierPath(roundedRect: CGRect(origin: CGPoint(x: fromRect.origin.x + diffX, y: fromRect.origin.y), size: fromRect.size), cornerRadius: fromRect.height / 2.0)
        let toRect = CGRect(origin: CGPoint(x: diffX, y: (fromRect.height - actionButtonFinalHeight) / 2.0), size: CGSize(width: self.countdownButtonNode.bounds.width, height: actionButtonFinalHeight))
        let toPath = UIBezierPath(roundedRect: toRect, cornerRadius: buttonCornerRadius)
        fillLayer.path = fromPath.cgPath
        self.countdownButtonNode.layer.mask = fillLayer

        let buttonSizeForAnimation = CGSize(width: self.countdownButtonNode.frame.size.width + diffX * 2.0, height: self.countdownButtonNode.frame.size.height)
        self.countdownButtonNode.updateLayout(size: buttonSizeForAnimation, transition: .immediate)
        self.countdownButtonNode.frame.origin.x -= diffX
        self.countdownButtonNode.frame.size = buttonSizeForAnimation
        
        self.countdownButtonNode.cornerRadius = self.countdownButtonNode.frame.size.height / 2.0
        transition.updateCornerRadius(node: self.countdownButtonNode, cornerRadius: buttonCornerRadius)

        transition.updatePath(layer: fillLayer, path: toPath.cgPath, completion: { [weak self]  _ in
            guard let strongSelf = self, let validLayout = self?.validLayout else {
                return
            }
            let _ = strongSelf.updateLayout(size: validLayout, transition: .immediate)
            strongSelf.countdownButtonNode.startAnimation()
        })
    }

    private func playStickerAnimation(from rect: CGRect) {
        let animationNode: AnimatedStickerNode = DefaultAnimatedStickerNodeImpl()
        let animationName = "RatingCallStars"
        let animationPlaybackMode: AnimatedStickerPlaybackMode = .once
        self.starContainerNode.addSubnode(animationNode)
        let sizeFactor: CGFloat = 2.5
        let size = CGSize(width: rect.width * sizeFactor, height: rect.height * sizeFactor)
        animationNode.updateLayout(size: size)
        animationNode.frame = CGRect(origin: .zero, size: size)
        animationNode.position = rect.center
        animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: animationName), width: Int(size.width), height: Int(size.height), playbackMode: animationPlaybackMode, mode: .direct(cachePathPrefix: nil))
        animationNode.visibility = true
    }
    
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        if self.animatedInProgress, let lastFinalSize = self.lastFinalSize {
            return lastFinalSize
        }
        
        var size = size
        size.width = min(size.width , 320.0)

        self.validLayout = size
        let contentSpacing: CGFloat = 10.0
        
        let contentInsets = UIEdgeInsets(top: 20.0, left: 20.0, bottom: 20.0, right: 20.0)
        
        let titleMaxWidth = size.width - contentInsets.left - contentInsets.right
        let titleSize = self.titleNode.measure(CGSize(width: titleMaxWidth, height: size.height))
        let titleOrigin = CGPoint(x: floor((size.width - titleSize.width) / 2.0), y: contentInsets.top)
        let titleFrame = CGRect(origin: titleOrigin, size: titleSize)
        transition.updateFrame(node: self.titleNode, frame: titleFrame)
        
        let subtitleSize = self.subtitleNode.measure(CGSize(width: titleMaxWidth, height: size.height))
        let subtitleFrame = CGRect(origin: CGPoint(x: floor((size.width - subtitleSize.width) / 2.0), y: titleFrame.maxY + contentSpacing), size: subtitleSize)
        transition.updateFrame(node: self.subtitleNode, frame: subtitleFrame)
        
        let starSize = CGSize(width: 42.0, height: 42.0)
        let starsOriginX = floorToScreenPixels((size.width - starSize.width * 5.0) / 2.0)
        self.starContainerNode.frame = CGRect(origin: CGPoint(x: starsOriginX, y: subtitleFrame.maxY + contentSpacing), size: CGSize(width: starSize.width * CGFloat(self.starNodes.count), height: starSize.height))
        for i in 0 ..< self.starNodes.count {
            let node = self.starNodes[i]
            transition.updateFrame(node: node, frame: CGRect(x: starSize.width * CGFloat(i), y: 0.0, width: starSize.width, height: starSize.height))
        }

        let contentSize = CGSize(width: size.width, height: titleSize.height + contentSpacing + subtitleSize.height + contentSpacing + starSize.height + contentInsets.top + contentInsets.bottom)
        transition.updateFrame(node: self.contentNode, frame: CGRect(origin: .zero, size: contentSize))
        transition.updateFrame(view: self.contentEffectView, frame: CGRect(origin: .zero, size: contentSize))
        
        let spaceAfterContent: CGFloat
        if size.height > contentSize.height + 66.0 + actionButtonHeight {
            spaceAfterContent = 66.0
        } else if size.height > contentSize.height + 24.0 + actionButtonHeight {
            spaceAfterContent = 24.0
        } else {
            spaceAfterContent = 12.0
        }
        
        let actionNodeFrame: CGRect
        if self.animationFinished {
            actionNodeFrame = CGRect(origin: CGPoint(x: 0.0, y: contentSize.height + spaceAfterContent + 3.0), size: CGSize(width: size.width, height: actionButtonFinalHeight))
        } else {
            actionNodeFrame = CGRect(origin: CGPoint(x: 0.0, y: contentSize.height + spaceAfterContent), size: CGSize(width: size.width, height: actionButtonHeight))
        }
        self.countdownButtonNode.updateLayout(size: actionNodeFrame.size, transition: .immediate)
        transition.updateFrame(node: self.countdownButtonNode, frame: actionNodeFrame)
        let lastFinalSize = CGSize(width: size.width, height: contentSize.height + spaceAfterContent + actionButtonHeight)
        self.lastFinalSize = lastFinalSize
        return lastFinalSize
    }
    
    @objc func panGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        if self.ratingDidApply {
            return
        }

        if gestureRecognizer.state == .began {
            self.hapticFeedback.prepareImpact(.medium)
        }

        let location = gestureRecognizer.location(in: self.starContainerNode.view)
        var selectedNode: ASButtonNode?
        for node in self.starNodes {
            if node.frame.contains(location) {
                selectedNode = node
                break
            }
        }
        if let selectedNode = selectedNode {
            switch gestureRecognizer.state {
                case .began, .changed:
                    self.hapticFeedback.impact(.medium)
                    self.starPressed(selectedNode)
                case .ended:
                    self.starReleased(selectedNode)
                case .cancelled:
                    self.resetStars()
                default:
                    break
            }
        } else {
            self.resetStars()
        }
    }
    
    private func resetStars() {
        for i in 0 ..< self.starNodes.count {
            let node = self.starNodes[i]
            node.isSelected = false
        }
    }
    
    @objc func starPressed(_ sender: ASButtonNode) {
        if let index = self.starNodes.firstIndex(of: sender) {
            self.rating = index + 1
            for i in 0 ..< self.starNodes.count {
                let node = self.starNodes[i]
                node.isSelected = i <= index
            }
        }
    }
    
    @objc func starReleased(_ sender: ASButtonNode) {
        if let index = self.starNodes.firstIndex(of: sender) {
            self.rating = index + 1
            for i in 0 ..< self.starNodes.count {
                let node = self.starNodes[i]
                node.isSelected = i <= index
            }
            if let rating = self.rating {
                self.ratingDidApply = true
                self.apply(rating)
                self.playStickerAnimation(from: self.starNodes[index].frame)
                self.hapticFeedback.prepareImpact()
            }
        }
    }
    
    @objc func actionPressed(_ sender: ASButtonNode) {
        self.dismiss()
    }
}

private func textTransparentImage(size: CGSize, text: String) -> UIImage? {
    UIGraphicsBeginImageContextWithOptions(size, true, 0)

    let context = UIGraphicsGetCurrentContext()
    context?.scaleBy(x: 1, y: -1)
    context?.translateBy(x: 0, y: -size.height)
    UIColor.white.setStroke()

    let attributes: [NSAttributedString.Key: Any] = [
        .font: buttonFont,
        .foregroundColor: UIColor.white
    ]
    let textSize = text.size(withAttributes: attributes)
    let point = CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2)
    text.draw(at: point, withAttributes: attributes)

    let maskImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    guard let cgimage = maskImage?.cgImage, let dataProvider = cgimage.dataProvider else { return nil }

    let bytesPerRow = cgimage.bytesPerRow
    let bitsPerPixel = cgimage.bitsPerPixel
    let width = cgimage.width
    let height = cgimage.height
    let bitsPerComponent = cgimage.bitsPerComponent

    guard let mask = CGImage(maskWidth: width, height: height, bitsPerComponent: bitsPerComponent, bitsPerPixel: bitsPerPixel, bytesPerRow: bytesPerRow, provider: dataProvider, decode: nil, shouldInterpolate: false) else { return nil }

    let rect = CGRect(origin: .zero, size: size)
    UIGraphicsBeginImageContextWithOptions(size, false, 0)
    UIGraphicsGetCurrentContext()?.clip(to: rect, mask: mask)
    UIColor.white.setFill()
    UIBezierPath(rect: rect).fill()
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return image
}
