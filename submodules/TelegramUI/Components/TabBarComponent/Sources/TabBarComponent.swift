import Foundation
import UIKit
import QuartzCore
import Display
import TelegramPresentationData
import ComponentFlow
import ComponentDisplayAdapters
import GlassBackgroundComponent
import MultilineTextComponent
import LottieComponent
import UIKitRuntimeUtils
import BundleIconComponent
import TextBadgeComponent

public final class TabBarComponent: Component {
    public final class Item: Equatable {
        public let item: UITabBarItem
        public let action: (Bool) -> Void
        public let contextAction: ((ContextGesture, ContextExtractedContentContainingView) -> Void)?
        
        fileprivate var id: AnyHashable {
            return AnyHashable(ObjectIdentifier(self.item))
        }
        
        public init(item: UITabBarItem, action: @escaping (Bool) -> Void, contextAction: ((ContextGesture, ContextExtractedContentContainingView) -> Void)?) {
            self.item = item
            self.action = action
            self.contextAction = contextAction
        }
        
        public static func ==(lhs: Item, rhs: Item) -> Bool {
            if lhs === rhs {
                return true
            }
            if lhs.item !== rhs.item {
                return false
            }
            if (lhs.contextAction == nil) != (rhs.contextAction == nil) {
                return false
            }
            return true
        }
    }
    
    public let theme: PresentationTheme
    public let items: [Item]
    public let selectedId: AnyHashable?
    public let isTablet: Bool
    
    public init(
        theme: PresentationTheme,
        items: [Item],
        selectedId: AnyHashable?,
        isTablet: Bool
    ) {
        self.theme = theme
        self.items = items
        self.selectedId = selectedId
        self.isTablet = isTablet
    }
    
    public static func ==(lhs: TabBarComponent, rhs: TabBarComponent) -> Bool {
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.items != rhs.items {
            return false
        }
        if lhs.selectedId != rhs.selectedId {
            return false
        }
        if lhs.isTablet != rhs.isTablet {
            return false
        }
        return true
    }
    
    public final class View: UIView, UITabBarDelegate, UIGestureRecognizerDelegate {
        private let backgroundView: GlassBackgroundView
        private let selectionView: GlassBackgroundView.ContentImageView
        private let contextGestureContainerView: ContextControllerSourceView
        private let nativeTabBar: UITabBar?

        private var itemViews: [AnyHashable: ComponentView<Empty>] = [:]
        private var selectedItemViews: [AnyHashable: ComponentView<Empty>] = [:]

        private var itemWithActiveContextGesture: AnyHashable?

        private var component: TabBarComponent?
        private weak var state: EmptyComponentState?

        private var isDraggingSelection: Bool = false
        private var draggingSelectionFrame: CGRect?
        private var panGestureRecognizer: UIPanGestureRecognizer?
        private var selectionAnimator: SelectionSpringAnimator?
        private var selectedOverlayView: UIImageView?
        private var overlayMaskLayer: CAShapeLayer?
        private var itemsContainerView: UIView?
        private var invertedMaskLayer: CAShapeLayer?
        private var shouldHideLiquidGlassOnAnimationComplete: Bool = false

        // Velocity tracking for morphing effect
        private var lastDragPosition: CGPoint = .zero
        private var lastDragTime: CFTimeInterval = 0
        private var currentDragVelocity: CGPoint = .zero

        private let liquidGlassScale: CGFloat = 1.33

        public var onLiquidGlassUpdate: ((_ frame: CGRect?, _ visible: Bool, _ continuousUpdate: Bool, _ velocity: CGPoint) -> Void)?
        public var onLiquidGlassHide: (() -> Void)?

        public override init(frame: CGRect) {
            self.backgroundView = GlassBackgroundView(frame: .zero, mode: .chatList)
            self.selectionView = GlassBackgroundView.ContentImageView()

            self.contextGestureContainerView = ContextControllerSourceView()
            self.contextGestureContainerView.isGestureEnabled = true
            
            if #available(iOS 26.0, *) {
                let nativeTabBar = UITabBar()
                self.nativeTabBar = nativeTabBar
                
                let itemFont = Font.semibold(10.0)
                let itemColor: UIColor = .clear
                
                nativeTabBar.traitOverrides.verticalSizeClass = .compact
                nativeTabBar.traitOverrides.horizontalSizeClass = .compact
                nativeTabBar.standardAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                    .foregroundColor: itemColor,
                    .font: itemFont
                ]
                nativeTabBar.standardAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                    .foregroundColor: itemColor,
                    .font: itemFont
                ]
                nativeTabBar.standardAppearance.inlineLayoutAppearance.normal.titleTextAttributes = [
                    .foregroundColor: itemColor,
                    .font: itemFont
                ]
                nativeTabBar.standardAppearance.inlineLayoutAppearance.selected.titleTextAttributes = [
                    .foregroundColor: itemColor,
                    .font: itemFont
                ]
                nativeTabBar.standardAppearance.compactInlineLayoutAppearance.normal.titleTextAttributes = [
                    .foregroundColor: itemColor,
                    .font: itemFont
                ]
                nativeTabBar.standardAppearance.compactInlineLayoutAppearance.selected.titleTextAttributes = [
                    .foregroundColor: itemColor,
                    .font: itemFont
                ]
            } else {
                self.nativeTabBar = nil
            }
            
            super.init(frame: frame)
            
            if #available(iOS 17.0, *) {
                self.traitOverrides.verticalSizeClass = .compact
                self.traitOverrides.horizontalSizeClass = .compact
            }
            
            self.addSubview(self.contextGestureContainerView)
            self.contextGestureContainerView.clipsToBounds = false

            if let nativeTabBar = self.nativeTabBar {
                self.contextGestureContainerView.addSubview(nativeTabBar)
                nativeTabBar.delegate = self
                /*let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(self.onLongPressGesture(_:)))
                longPressGesture.delegate = self
                self.addGestureRecognizer(longPressGesture)*/
            } else {
                self.contextGestureContainerView.addSubview(self.backgroundView)

                let itemsContainer = UIView()
                self.itemsContainerView = itemsContainer
                self.contextGestureContainerView.addSubview(itemsContainer)

                self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.onTapGesture(_:))))

                let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.onPanGesture(_:)))
                panGesture.delegate = self
                self.addGestureRecognizer(panGesture)
                self.panGestureRecognizer = panGesture
            }
            
            self.contextGestureContainerView.shouldBegin = { [weak self] point in
                guard let self, let component = self.component else {
                    return false
                }
                for (id, itemView) in self.itemViews {
                    if let itemView = itemView.view {
                        if self.convert(itemView.bounds, from: itemView).contains(point) {
                            guard let item = component.items.first(where: { $0.id == id }) else {
                                return false
                            }
                            if item.contextAction == nil {
                                return false
                            }
                            
                            self.itemWithActiveContextGesture = id
                            
                            let startPoint = point
                            self.contextGestureContainerView.contextGesture?.externalUpdated = { [weak self] _, point in
                                guard let self else {
                                    return
                                }
                                
                                let dist = sqrt(pow(startPoint.x - point.x, 2.0) + pow(startPoint.y - point.y, 2.0))
                                if dist > 10.0 {
                                    self.contextGestureContainerView.contextGesture?.cancel()
                                }
                            }
                            
                            return true
                        }
                    }
                }
                return false
            }
            self.contextGestureContainerView.customActivationProgress = { [weak self] _, _ in
                let _ = self
                return
                /*guard let self, let itemWithActiveContextGesture = self.itemWithActiveContextGesture else {
                    return
                }
                guard let itemView = self.itemViews[itemWithActiveContextGesture]?.view else {
                    return
                }
                let scaleSide = itemView.bounds.width
                let minScale: CGFloat = max(0.7, (scaleSide - 15.0) / scaleSide)
                let currentScale = 1.0 * (1.0 - progress) + minScale * progress

                switch update {
                case .update:
                    let sublayerTransform = CATransform3DScale(CATransform3DIdentity, currentScale, currentScale, 1.0)
                    itemView.layer.sublayerTransform = sublayerTransform
                case .begin:
                    let sublayerTransform = CATransform3DScale(CATransform3DIdentity, currentScale, currentScale, 1.0)
                    itemView.layer.sublayerTransform = sublayerTransform
                case .ended:
                    let sublayerTransform = CATransform3DScale(CATransform3DIdentity, currentScale, currentScale, 1.0)
                    let previousTransform = itemView.layer.sublayerTransform
                    itemView.layer.sublayerTransform = sublayerTransform

                    itemView.layer.animate(from: NSValue(caTransform3D: previousTransform), to: NSValue(caTransform3D: sublayerTransform), keyPath: "sublayerTransform", timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, duration: 0.2)
                }*/
            }
            self.contextGestureContainerView.activated = { [weak self] gesture, _ in
                guard let self, let component = self.component else {
                    return
                }

                if self.isDraggingSelection {
                    self.isDraggingSelection = false
                    self.draggingSelectionFrame = nil
                    self.selectionAnimator?.stop()
                    self.panGestureRecognizer?.state = .cancelled
                    self.state?.updated(transition: .spring(duration: 0.3))
                }

                guard let itemWithActiveContextGesture = self.itemWithActiveContextGesture else {
                    return
                }

                var itemView: ItemComponent.View?
                if self.nativeTabBar != nil {
                    itemView = self.selectedItemViews[itemWithActiveContextGesture]?.view as? ItemComponent.View
                } else {
                    itemView = self.itemViews[itemWithActiveContextGesture]?.view as? ItemComponent.View
                }

                guard let itemView else {
                    return
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        return
                    }
                    if let nativeTabBar = self.nativeTabBar {
                        func cancelGestures(view: UIView) {
                            for recognizer in view.gestureRecognizers ?? [] {
                                if NSStringFromClass(type(of: recognizer)).contains("sSelectionGestureRecognizer") {
                                    recognizer.state = .cancelled
                                }
                            }
                            for subview in view.subviews {
                                cancelGestures(view: subview)
                            }
                        }

                        cancelGestures(view: nativeTabBar)
                    }
                }

                guard let item = component.items.first(where: { $0.id == itemWithActiveContextGesture }) else {
                    return
                }
                item.contextAction?(gesture, itemView.contextContainerView)
            }
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let component = self.component else {
                return
            }
            if let index = tabBar.items?.firstIndex(where: { $0 === item }) {
                if index < component.items.count {
                    component.items[index].action(false)
                }
            }
        }

        public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer is UIPanGestureRecognizer {
                if otherGestureRecognizer === self.contextGestureContainerView.contextGesture {
                    return false
                }
            }
            return true
        }
        
        @objc private func onLongPressGesture(_ recognizer: UILongPressGestureRecognizer) {
            if case .began = recognizer.state {
                if let nativeTabBar = self.nativeTabBar {
                    func cancelGestures(view: UIView) {
                        for recognizer in view.gestureRecognizers ?? [] {
                            if NSStringFromClass(type(of: recognizer)).contains("sSelectionGestureRecognizer") {
                                recognizer.state = .cancelled
                            }
                        }
                        for subview in view.subviews {
                            cancelGestures(view: subview)
                        }
                    }
                    
                    cancelGestures(view: nativeTabBar)
                }
            }
        }
        
        @objc private func onTapGesture(_ recognizer: UITapGestureRecognizer) {
            guard let component = self.component else {
                return
            }
            if case .ended = recognizer.state {
                let point = recognizer.location(in: self)
                var closestItemView: (AnyHashable, CGFloat)?
                for (id, itemView) in self.itemViews {
                    guard let itemView = itemView.view else {
                        continue
                    }
                    let distance = abs(point.x - itemView.center.x)
                    if let previousClosestItemView = closestItemView {
                        if previousClosestItemView.1 > distance {
                            closestItemView = (id, distance)
                        }
                    } else {
                        closestItemView = (id, distance)
                    }
                }
                
                if let (id, _) = closestItemView {
                    guard let item = component.items.first(where: { $0.id == id }) else {
                        return
                    }
                    item.action(false)
                    /*if previousSelectedIndex != closestNode.0 {
                     if let selectedIndex = self.selectedIndex, let _ = self.tabBarItems[selectedIndex].item.animationName {
                     container.imageNode.animationNode.play(firstFrame: false, fromIndex: nil)
                     }
                     }*/
                }
            }
        }

        @objc private func onPanGesture(_ recognizer: UIPanGestureRecognizer) {
            guard self.nativeTabBar == nil, let component = self.component else {
                return
            }

            let point = recognizer.location(in: self)

            switch recognizer.state {
            case .began:
                self.isDraggingSelection = true
                self.shouldHideLiquidGlassOnAnimationComplete = false

                // Initialize velocity tracking
                self.lastDragPosition = point
                self.lastDragTime = CACurrentMediaTime()
                self.currentDragVelocity = .zero

                let transition = ComponentTransition.spring(duration: 0.2)
//                transition.setScale(view: self.contextGestureContainerView, scale: 1.03)
                transition.setAlpha(view: selectionView, alpha: 0.0)

                if let selectedId = component.selectedId,
                   let selectedItemView = self.itemViews[selectedId],
                   let item = component.items.first(where: { $0.id == selectedId }) {
                    let _ = selectedItemView.update(
                        transition: .immediate,
                        component: AnyComponent(ItemComponent(
                            item: item,
                            theme: component.theme,
                            isSelected: false
                        )),
                        environment: {},
                        containerSize: selectedItemView.view?.bounds.size ?? .zero
                    )
                }

                if let overlayImage = self.createSelectedOverlayImage() {
                    let overlayView = UIImageView(image: overlayImage)
                    overlayView.frame = self.contextGestureContainerView.bounds
                    self.contextGestureContainerView.addSubview(overlayView)
                    self.selectedOverlayView = overlayView

                    let maskLayer = CAShapeLayer()
                    let maskFrame = self.adjustFrameForContainerScale(self.liquidGlassFrame(for: self.selectionView.frame))
                    let cornerRadius = maskFrame.height * 0.5
                    maskLayer.path = UIBezierPath(roundedRect: maskFrame, cornerRadius: cornerRadius).cgPath
                    overlayView.layer.mask = maskLayer
                    self.overlayMaskLayer = maskLayer

                    let invertedMaskLayer = CAShapeLayer()
                    invertedMaskLayer.fillRule = .evenOdd
                    let invertedPath = UIBezierPath(rect: self.contextGestureContainerView.bounds)
                    invertedPath.append(UIBezierPath(roundedRect: maskFrame, cornerRadius: cornerRadius))
                    invertedMaskLayer.path = invertedPath.cgPath
                    self.itemsContainerView?.layer.mask = invertedMaskLayer
                    self.invertedMaskLayer = invertedMaskLayer
                }

                if self.selectionAnimator == nil {
                    let animator = SelectionSpringAnimator()
                    animator.onFrameChanged = { [weak self] frame in
                        guard let self else { return }
                        self.draggingSelectionFrame = frame
                        self.selectionView.frame = frame
                        self.onLiquidGlassUpdate?(self.liquidGlassFrame(for: frame), true, true, self.currentDragVelocity)

                        if let maskLayer = self.overlayMaskLayer {
                            CATransaction.begin()
                            CATransaction.setDisableActions(true)
                            let maskFrame = self.adjustFrameForContainerScale(self.liquidGlassFrame(for: frame))
                            let cornerRadius = maskFrame.height * 0.5
                            maskLayer.path = UIBezierPath(roundedRect: maskFrame, cornerRadius: cornerRadius).cgPath
                            CATransaction.commit()

                            if let invertedMaskLayer = self.invertedMaskLayer {
                                CATransaction.begin()
                                CATransaction.setDisableActions(true)
                                let invertedPath = UIBezierPath(rect: self.contextGestureContainerView.bounds)
                                invertedPath.append(UIBezierPath(roundedRect: maskFrame, cornerRadius: cornerRadius))
                                invertedMaskLayer.path = invertedPath.cgPath
                                CATransaction.commit()
                            }
                        }
                    }
                    animator.onAnimationCompleted = { [weak self] in
                        guard let self, self.shouldHideLiquidGlassOnAnimationComplete else { return }
                        self.shouldHideLiquidGlassOnAnimationComplete = false
                        self.onLiquidGlassHide?()
                    }
                    self.selectionAnimator = animator
                }

                if let targetFrame = self.calculateSelectionFrame(for: point) {
                    self.selectionAnimator?.frameTemplate = targetFrame
                    self.selectionAnimator?.setCurrentX(self.selectionView.frame.origin.x)
                    self.selectionAnimator?.animateTo(targetFrame.origin.x)
                }

            case .changed:
                // Track drag velocity
                let currentTime = CACurrentMediaTime()
                let dt = currentTime - self.lastDragTime
                if dt > 0.001 {
                    self.currentDragVelocity = CGPoint(
                        x: (point.x - self.lastDragPosition.x) / dt,
                        y: (point.y - self.lastDragPosition.y) / dt
                    )
                }
                self.lastDragPosition = point
                self.lastDragTime = currentTime

                if let targetFrame = self.calculateSelectionFrame(for: point) {
                    self.selectionAnimator?.frameTemplate = targetFrame
                    self.selectionAnimator?.updateTarget(targetFrame.origin.x)
                }

            case .ended, .cancelled:
                self.isDraggingSelection = false
                self.shouldHideLiquidGlassOnAnimationComplete = true

                let scaleTransition = ComponentTransition(animation: .curve(duration: 0.3, curve: .easeInOut))
                scaleTransition.setScale(view: self.contextGestureContainerView, scale: 1.0)
                scaleTransition.setAlpha(view: selectionView, alpha: 1.0)

                let removeOverlay = self.selectedOverlayView
                self.selectedOverlayView = nil
                self.overlayMaskLayer = nil
                self.invertedMaskLayer = nil
                self.itemsContainerView?.layer.mask = nil

                if let removeOverlay {
                    let transition = ComponentTransition(animation: .curve(duration: 0.15, curve: .easeInOut))
                    transition.setAlpha(view: removeOverlay, alpha: 0.0, completion: { [weak removeOverlay] _ in
                        removeOverlay?.removeFromSuperview()
                    })
                }

                if let (id, frame) = self.findClosestItem(to: point) {
                    self.draggingSelectionFrame = nil
                    let velocity = recognizer.velocity(in: self)
                    self.selectionAnimator?.frameTemplate = frame
                    self.selectionAnimator?.addVelocity(velocity.x * 0.1)
                    self.selectionAnimator?.animateTo(frame.origin.x)

                    if let item = component.items.first(where: { $0.id == id }) {
                        if let selectedItemView = self.itemViews[id] {
                            let _ = selectedItemView.update(
                                transition: .immediate,
                                component: AnyComponent(ItemComponent(
                                    item: item,
                                    theme: component.theme,
                                    isSelected: true
                                )),
                                environment: {},
                                containerSize: selectedItemView.view?.bounds.size ?? .zero
                            )
                        }
                        item.action(false)
                    }
                }

            default:
                break
            }
        }

        private func findClosestItemFrame(to point: CGPoint) -> CGRect? {
            var closestFrame: CGRect?
            var minDistance: CGFloat = .greatestFiniteMagnitude

            for (_, itemView) in self.itemViews {
                guard let view = itemView.view else { continue }
                let frame = self.convert(view.bounds, from: view)
                let distance = abs(point.x - frame.midX)
                if distance < minDistance {
                    minDistance = distance
                    closestFrame = frame
                }
            }
            return closestFrame
        }

        private func findClosestItem(to point: CGPoint) -> (AnyHashable, CGRect)? {
            var closest: (AnyHashable, CGRect)?
            var minDistance: CGFloat = .greatestFiniteMagnitude

            for (id, itemView) in self.itemViews {
                guard let view = itemView.view else { continue }
                let frame = self.convert(view.bounds, from: view)
                let distance = abs(point.x - frame.midX)
                if distance < minDistance {
                    minDistance = distance
                    closest = (id, frame)
                }
            }
            return closest
        }

        private func liquidGlassFrame(for selectionFrame: CGRect) -> CGRect {
            return CGRect(
                x: selectionFrame.origin.x - selectionFrame.width * (liquidGlassScale - 1) / 2,
                y: selectionFrame.origin.y - selectionFrame.height * (liquidGlassScale - 1) / 2,
                width: selectionFrame.width * liquidGlassScale,
                height: selectionFrame.height * liquidGlassScale
            )
        }

        private func adjustFrameForContainerScale(_ frame: CGRect) -> CGRect {
            let scale = self.contextGestureContainerView.layer.transform.m11
            guard scale != 1.0 else { return frame }

            let containerSize = self.contextGestureContainerView.bounds.size
            let centerX = containerSize.width / 2.0
            let centerY = containerSize.height / 2.0

            return CGRect(
                x: centerX + (frame.origin.x - centerX) / scale,
                y: centerY + (frame.origin.y - centerY) / scale,
                width: frame.width / scale,
                height: frame.height / scale
            )
        }

        private func calculateSelectionFrame(for point: CGPoint) -> CGRect? {
            let sortedItems = self.itemViews.compactMap { (id, itemView) -> (AnyHashable, CGRect)? in
                guard let view = itemView.view else { return nil }
                return (id, self.convert(view.bounds, from: view))
            }.sorted { $0.1.midX < $1.1.midX }

            guard !sortedItems.isEmpty else { return nil }

            let minX = sortedItems.first!.1.midX
            let maxX = sortedItems.last!.1.midX
            let clampedX = max(minX, min(maxX, point.x))

            for i in 0..<sortedItems.count - 1 {
                let left = sortedItems[i].1
                let right = sortedItems[i + 1].1

                if clampedX >= left.midX && clampedX <= right.midX {
                    let t = (clampedX - left.midX) / (right.midX - left.midX)
                    let interpolatedX = left.origin.x + (right.origin.x - left.origin.x) * t
                    return CGRect(origin: CGPoint(x: interpolatedX, y: left.origin.y), size: left.size)
                }
            }

            return findClosestItemFrame(to: point)
        }

        private func createSelectedOverlayImage() -> UIImage? {
            let containerSize = self.contextGestureContainerView.bounds.size
            guard containerSize.width > 0 && containerSize.height > 0 else { return nil }

            let renderer = UIGraphicsImageRenderer(size: containerSize)
            let image = renderer.image { ctx in
                UIColor.clear.setFill()
                ctx.fill(CGRect(origin: .zero, size: containerSize))

                for (id, selectedItemView) in self.selectedItemViews {
                    guard let view = selectedItemView.view else { continue }
                    guard let itemView = self.itemViews[id]?.view else { continue }

                    let itemFrame = itemView.frame
                    let scale: CGFloat = 1.25

                    ctx.cgContext.saveGState()
                    ctx.cgContext.translateBy(x: itemFrame.midX, y: itemFrame.midY)
                    ctx.cgContext.scaleBy(x: scale, y: scale)
                    ctx.cgContext.translateBy(x: -itemFrame.width / 2.0, y: -itemFrame.height / 2.0)
                    view.layer.render(in: ctx.cgContext)
                    ctx.cgContext.restoreGState()
                }
            }
            return image
        }

        override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            return super.hitTest(point, with: event)
        }
        
        public func frameForItem(at index: Int) -> CGRect? {
            guard let component = self.component else {
                return nil
            }
            if index < 0 || index >= component.items.count {
                return nil
            }
            guard let itemView = self.itemViews[component.items[index].id]?.view else {
                return nil
            }
            return self.convert(itemView.bounds, from: itemView)
        }

        public func setGlassSourceView(_ view: UIView?) {
            self.backgroundView.setSourceView(view)
        }

        public func getBackgroundView() -> UIView {
            return self.backgroundView
        }
        
        public override func didMoveToWindow() {
            super.didMoveToWindow()
            
            self.state?.updated()
        }
        
        func update(component: TabBarComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            let innerInset: CGFloat = 3.0
            
            let availableSize = CGSize(width: min(500.0, availableSize.width), height: availableSize.height)
            
            let previousComponent = self.component
            self.component = component
            self.state = state
            
            self.overrideUserInterfaceStyle = component.theme.overallDarkAppearance ? .dark : .light
            
            if let nativeTabBar = self.nativeTabBar {
                if previousComponent?.items.map(\.item.title) != component.items.map(\.item.title) {
                    let items: [UITabBarItem] = (0 ..< component.items.count).map { i in
                        return UITabBarItem(title: component.items[i].item.title, image: nil, tag: i)
                    }
                    nativeTabBar.items = items
                    for (_, itemView) in self.itemViews {
                        itemView.view?.removeFromSuperview()
                    }
                    for (_, selectedItemView) in self.selectedItemViews {
                        selectedItemView.view?.removeFromSuperview()
                    }
                    if let index = component.items.firstIndex(where: { $0.id == component.selectedId }) {
                        nativeTabBar.selectedItem = nativeTabBar.items?[index]
                    }
                }
                
                nativeTabBar.frame = CGRect(origin: CGPoint(), size: CGSize(width: availableSize.width, height: component.isTablet ? 74.0 : 83.0))
                nativeTabBar.layoutSubviews()
            }
            
            var nativeItemContainers: [Int: UIView] = [:]
            var nativeSelectedItemContainers: [Int: UIView] = [:]
            if let nativeTabBar = self.nativeTabBar {
                for subview in nativeTabBar.subviews {
                    if NSStringFromClass(type(of: subview)).contains("PlatterView") {
                        for subview in subview.subviews {
                            if NSStringFromClass(type(of: subview)).hasSuffix("SelectedContentView") {
                                for subview in subview.subviews {
                                    if NSStringFromClass(type(of: subview)).hasSuffix("TabButton") {
                                        nativeSelectedItemContainers[nativeSelectedItemContainers.count] = subview
                                    }
                                }
                            } else if NSStringFromClass(type(of: subview)).hasSuffix("ContentView") {
                                for subview in subview.subviews {
                                    if NSStringFromClass(type(of: subview)).hasSuffix("TabButton") {
                                        nativeItemContainers[nativeItemContainers.count] = subview
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            var itemSize = CGSize(width: floor((availableSize.width - innerInset * 2.0) / CGFloat(component.items.count)), height: 56.0)
            itemSize.width = min(94.0, itemSize.width)
            
            if let itemContainer = nativeItemContainers[0] {
                itemSize = itemContainer.bounds.size
            }
            
            let contentHeight = itemSize.height + innerInset * 2.0
            var contentWidth: CGFloat = innerInset
            
            if self.selectionView.image?.size.height != itemSize.height {
                self.selectionView.image = generateStretchableFilledCircleImage(radius: itemSize.height * 0.5, color: .white)?.withRenderingMode(.alwaysTemplate)
            }
            self.selectionView.tintColor = component.theme.list.itemPrimaryTextColor.withMultipliedAlpha(0.05)
            
            var validIds: [AnyHashable] = []
            var selectionFrame: CGRect?
            for index in 0 ..< component.items.count {
                let item = component.items[index]
                validIds.append(item.id)
                
                let itemView: ComponentView<Empty>
                var itemTransition = transition
                
                if let current = self.itemViews[item.id] {
                    itemView = current
                } else {
                    itemTransition = itemTransition.withAnimation(.none)
                    itemView = ComponentView()
                    self.itemViews[item.id] = itemView
                }
                
                let selectedItemView: ComponentView<Empty>
                if let current = self.selectedItemViews[item.id] {
                    selectedItemView = current
                } else {
                    selectedItemView = ComponentView()
                    self.selectedItemViews[item.id] = selectedItemView
                }
                
                let isItemSelected = component.selectedId == item.id
                
                let _ = itemView.update(
                    transition: itemTransition,
                    component: AnyComponent(ItemComponent(
                        item: item,
                        theme: component.theme,
                        isSelected: self.nativeTabBar == nil ? isItemSelected : false
                    )),
                    environment: {},
                    containerSize: itemSize
                )
                let _ = selectedItemView.update(
                    transition: itemTransition,
                    component: AnyComponent(ItemComponent(
                        item: item,
                        theme: component.theme,
                        isSelected: true
                    )),
                    environment: {},
                    containerSize: itemSize
                )
                
                let itemFrame = CGRect(origin: CGPoint(x: contentWidth, y: floor((contentHeight - itemSize.height) * 0.5)), size: itemSize)
                if let itemComponentView = itemView.view as? ItemComponent.View, let selectedItemComponentView = selectedItemView.view as? ItemComponent.View {
                    if itemComponentView.superview == nil {
                        itemComponentView.isUserInteractionEnabled = false
                        selectedItemComponentView.isUserInteractionEnabled = false
                        
                        if self.nativeTabBar != nil {
                            if let itemContainer = nativeItemContainers[index] {
                                itemContainer.addSubview(itemComponentView)
                            }
                            if let itemContainer = nativeSelectedItemContainers[index] {
                                itemContainer.addSubview(selectedItemComponentView)
                            }
                        } else {
                            self.itemsContainerView?.addSubview(itemComponentView)
                        }
                    }
                    if self.nativeTabBar != nil {
                        if let parentView = itemComponentView.superview {
                            let itemFrame = CGRect(origin: CGPoint(x: floor((parentView.bounds.width - itemSize.width) * 0.5), y: floor((parentView.bounds.height - itemSize.height) * 0.5)), size: itemSize)
                            itemTransition.setFrame(view: itemComponentView, frame: itemFrame)
                            itemTransition.setFrame(view: selectedItemComponentView, frame: itemFrame)
                        }
                    } else {
                        itemTransition.setFrame(view: itemComponentView, frame: itemFrame)
                    }
                    
                    if let previousComponent, previousComponent.selectedId != item.id, isItemSelected {
                        itemComponentView.playSelectionAnimation()
                        selectedItemComponentView.playSelectionAnimation()
                    }
                }
                if isItemSelected {
                    selectionFrame = itemFrame
                }
                
                contentWidth += itemFrame.width
            }
            contentWidth += innerInset
            
            var removeIds: [AnyHashable] = []
            for (id, itemView) in self.itemViews {
                if !validIds.contains(id) {
                    removeIds.append(id)
                    itemView.view?.removeFromSuperview()
                    self.selectedItemViews[id]?.view?.removeFromSuperview()
                }
            }
            for id in removeIds {
                self.itemViews.removeValue(forKey: id)
                self.selectedItemViews.removeValue(forKey: id)
            }
            
            let effectiveSelectionFrame = self.isDraggingSelection ? self.draggingSelectionFrame : selectionFrame
            if let effectiveSelectionFrame, self.nativeTabBar == nil {
                var selectionViewTransition = transition
                if self.selectionView.superview == nil {
                    selectionViewTransition = selectionViewTransition.withAnimation(.none)
                    self.backgroundView.contentView.addSubview(self.selectionView)
                }
                if !self.isDraggingSelection {
                    selectionViewTransition.setFrame(view: self.selectionView, frame: effectiveSelectionFrame)
//                    self.onLiquidGlassUpdate?(self.liquidGlassFrame(for: effectiveSelectionFrame), true, true)
                }
            } else if self.selectionView.superview != nil && !self.isDraggingSelection {
                self.selectionView.removeFromSuperview()
                self.onLiquidGlassUpdate?(nil, false, false, .zero)
            }
            
            let size = CGSize(width: min(availableSize.width, contentWidth), height: contentHeight)

            transition.setFrame(view: self.backgroundView, frame: CGRect(origin: CGPoint(), size: size))
            self.backgroundView.update(size: size, cornerRadius: size.height * 0.5, isDark: component.theme.overallDarkAppearance, tintColor: .init(kind: .panel, color: component.theme.chat.inputPanel.inputBackgroundColor.withMultipliedAlpha(0.7)), transition: transition)

            if let itemsContainerView = self.itemsContainerView {
                transition.setFrame(view: itemsContainerView, frame: CGRect(origin: CGPoint(), size: size))
            }

            if self.nativeTabBar != nil {
                let finalSize = CGSize(width: availableSize.width, height: 62.0)
                transition.setFrame(view: self.contextGestureContainerView, frame: CGRect(origin: CGPoint(), size: finalSize))
                return finalSize
            } else {
                transition.setFrame(view: self.contextGestureContainerView, frame: CGRect(origin: CGPoint(), size: size))

                // Configure radial glow shadow
                let shadowPath = UIBezierPath(
                    roundedRect: CGRect(origin: .zero, size: size),
                    cornerRadius: size.height * 0.5
                ).cgPath
                self.contextGestureContainerView.layer.shadowPath = shadowPath
                self.contextGestureContainerView.layer.shadowColor = component.theme.overallDarkAppearance
                    ? UIColor(white: 1.0, alpha: 1.0).cgColor  // Light shadow in dark mode
                    : UIColor(white: 0.0, alpha: 1.0).cgColor  // Dark shadow in light mode
                self.contextGestureContainerView.layer.shadowOpacity = 0.04
                self.contextGestureContainerView.layer.shadowOffset = .zero
                self.contextGestureContainerView.layer.shadowRadius = 10.0

                return size
            }
        }
    }
    
    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

private final class ItemComponent: Component {
    let item: TabBarComponent.Item
    let theme: PresentationTheme
    let isSelected: Bool
    
    init(item: TabBarComponent.Item, theme: PresentationTheme, isSelected: Bool) {
        self.item = item
        self.theme = theme
        self.isSelected = isSelected
    }
    
    static func ==(lhs: ItemComponent, rhs: ItemComponent) -> Bool {
        if lhs.item != rhs.item {
            return false
        }
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.isSelected != rhs.isSelected {
            return false
        }
        return true
    }
    
    final class View: UIView {
        let contextContainerView: ContextExtractedContentContainingView
        
        private var imageIcon: ComponentView<Empty>?
        private var animationIcon: ComponentView<Empty>?
        private let title = ComponentView<Empty>()
        private var badge: ComponentView<Empty>?
        
        private var component: ItemComponent?
        private weak var state: EmptyComponentState?
        
        private var setImageListener: Int?
        private var setSelectedImageListener: Int?
        private var setBadgeListener: Int?
        
        override init(frame: CGRect) {
            self.contextContainerView = ContextExtractedContentContainingView()
            
            super.init(frame: frame)
            
            self.addSubview(self.contextContainerView)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        deinit {
            if let component = self.component {
                if let setImageListener = self.setImageListener {
                    component.item.item.removeSetImageListener(setImageListener)
                }
                if let setSelectedImageListener = self.setSelectedImageListener {
                    component.item.item.removeSetSelectedImageListener(setSelectedImageListener)
                }
                if let setBadgeListener = self.setBadgeListener {
                    component.item.item.removeSetBadgeListener(setBadgeListener)
                }
            }
        }
        
        func playSelectionAnimation() {
            if let animationIconView = self.animationIcon?.view as? LottieComponent.View {
                animationIconView.playOnce()
            }
        }
        
        func update(component: ItemComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            let previousComponent = self.component
            
            if previousComponent?.item.item !== component.item.item {
                if let setImageListener = self.setImageListener {
                    self.component?.item.item.removeSetImageListener(setImageListener)
                }
                if let setSelectedImageListener = self.setSelectedImageListener {
                    self.component?.item.item.removeSetSelectedImageListener(setSelectedImageListener)
                }
                if let setBadgeListener = self.setBadgeListener {
                    self.component?.item.item.removeSetBadgeListener(setBadgeListener)
                }
                self.setImageListener = component.item.item.addSetImageListener { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.state?.updated(transition: .immediate, isLocal: true)
                }
                self.setSelectedImageListener = component.item.item.addSetSelectedImageListener { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.state?.updated(transition: .immediate, isLocal: true)
                }
                self.setBadgeListener = UITabBarItem_addSetBadgeListener(component.item.item) { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.state?.updated(transition: .immediate, isLocal: true)
                }
            }
            
            self.component = component
            self.state = state
            
            if let animationName = component.item.item.animationName {
                if let imageIcon = self.imageIcon {
                    self.imageIcon = nil
                    imageIcon.view?.removeFromSuperview()
                }
                
                let animationIcon: ComponentView<Empty>
                var iconTransition = transition
                if let current = self.animationIcon {
                    animationIcon = current
                } else {
                    iconTransition = iconTransition.withAnimation(.none)
                    animationIcon = ComponentView()
                    self.animationIcon = animationIcon
                }
                
                let iconSize = animationIcon.update(
                    transition: iconTransition,
                    component: AnyComponent(LottieComponent(
                        content: LottieComponent.AppBundleContent(
                            name: animationName
                        ),
                        color: component.isSelected ? component.theme.rootController.tabBar.selectedTextColor : component.theme.rootController.tabBar.textColor,
                        placeholderColor: nil,
                        startingPosition: .end,
                        size: CGSize(width: 48.0, height: 48.0),
                        loop: false
                    )),
                    environment: {},
                    containerSize: CGSize(width: 48.0, height: 48.0)
                )
                let iconFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - iconSize.width) * 0.5), y: -4.0), size: iconSize).offsetBy(dx: component.item.item.animationOffset.x, dy: component.item.item.animationOffset.y)
                if let animationIconView = animationIcon.view {
                    if animationIconView.superview == nil {
                        if let badgeView = self.badge?.view {
                            self.contextContainerView.contentView.insertSubview(animationIconView, belowSubview: badgeView)
                        } else {
                            self.contextContainerView.contentView.addSubview(animationIconView)
                        }
                    }
                    iconTransition.setFrame(view: animationIconView, frame: iconFrame)
                }
            } else {
                if let animationIcon = self.animationIcon {
                    self.animationIcon = nil
                    animationIcon.view?.removeFromSuperview()
                }
                
                let imageIcon: ComponentView<Empty>
                var iconTransition = transition
                if let current = self.imageIcon {
                    imageIcon = current
                } else {
                    iconTransition = iconTransition.withAnimation(.none)
                    imageIcon = ComponentView()
                    self.imageIcon = imageIcon
                }
                
                let iconSize = imageIcon.update(
                    transition: iconTransition,
                    component: AnyComponent(Image(
                        image: component.isSelected ? component.item.item.selectedImage : component.item.item.image,
                        tintColor: nil,
                        contentMode: .center
                    )),
                    environment: {},
                    containerSize: CGSize(width: 100.0, height: 100.0)
                )
                let iconFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - iconSize.width) * 0.5), y: 3.0), size: iconSize)
                if let imageIconView = imageIcon.view {
                    if imageIconView.superview == nil {
                        if let badgeView = self.badge?.view {
                            self.contextContainerView.contentView.insertSubview(imageIconView, belowSubview: badgeView)
                        } else {
                            self.contextContainerView.contentView.addSubview(imageIconView)
                        }
                    }
                    iconTransition.setFrame(view: imageIconView, frame: iconFrame)
                }
            }
            
            let titleSize = self.title.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: component.item.item.title ?? " ", font: Font.semibold(10.0), textColor: component.isSelected ? component.theme.rootController.tabBar.selectedTextColor : component.theme.rootController.tabBar.textColor))
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width, height: 100.0)
            )
            let titleFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - titleSize.width) * 0.5), y: availableSize.height - 8.0 - titleSize.height), size: titleSize)
            if let titleView = self.title.view {
                if titleView.superview == nil {
                    self.contextContainerView.contentView.addSubview(titleView)
                }
                titleView.frame = titleFrame
            }
            
            if let badgeText = component.item.item.badgeValue, !badgeText.isEmpty {
                let badge: ComponentView<Empty>
                var badgeTransition = transition
                if let current = self.badge {
                    badge = current
                } else {
                    badgeTransition = badgeTransition.withAnimation(.none)
                    badge = ComponentView()
                    self.badge = badge
                }
                let badgeSize = badge.update(
                    transition: badgeTransition,
                    component: AnyComponent(TextBadgeComponent(
                        text: badgeText,
                        font: Font.regular(13.0),
                        background: component.theme.rootController.tabBar.badgeBackgroundColor,
                        foreground: component.theme.rootController.tabBar.badgeTextColor,
                        insets: UIEdgeInsets(top: 0.0, left: 6.0, bottom: 1.0, right: 6.0)
                    )),
                    environment: {},
                    containerSize: CGSize(width: 100.0, height: 100.0)
                )
                let contentWidth: CGFloat = 25.0
                let badgeFrame = CGRect(origin: CGPoint(x: floor(availableSize.width / 2.0) + contentWidth - badgeSize.width - 1.0, y: 5.0), size: badgeSize)
                if let badgeView = badge.view {
                    if badgeView.superview == nil {
                        self.contextContainerView.contentView.addSubview(badgeView)
                    }
                    badgeTransition.setFrame(view: badgeView, frame: badgeFrame)
                }
            } else if let badge = self.badge {
                self.badge = nil
                badge.view?.removeFromSuperview()
            }
            
            transition.setFrame(view: self.contextContainerView, frame: CGRect(origin: CGPoint(), size: availableSize))
            transition.setFrame(view: self.contextContainerView.contentView, frame: CGRect(origin: CGPoint(), size: availableSize))
            self.contextContainerView.contentRect = CGRect(origin: CGPoint(), size: availableSize)
            
            return availableSize
        }
    }
    
    func makeView() -> View {
        return View(frame: CGRect())
    }
    
    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

private final class SelectionSpringAnimator {
    var stiffness: CGFloat = 400
    var damping: CGFloat = 25
    var mass: CGFloat = 1.0

    private var displayLink: SharedDisplayLinkDriver.Link?
    private(set) var currentX: CGFloat = 0
    private(set) var currentVelocity: CGFloat = 0
    private var targetX: CGFloat = 0

    var frameTemplate: CGRect = .zero

    private let velocityThreshold: CGFloat = 15.0
    private let positionThreshold: CGFloat = 7.0

    private(set) var isTracking: Bool = false

    var onFrameChanged: ((CGRect) -> Void)?
    var onAnimationCompleted: (() -> Void)?

    func setCurrentX(_ x: CGFloat) {
        self.currentX = x
        self.currentVelocity = 0
        self.isTracking = false
    }

    func animateTo(_ x: CGFloat, initialVelocity: CGFloat = 0) {
        self.targetX = x
        self.currentVelocity = initialVelocity
        self.isTracking = false
        self.startDisplayLink()
    }

    func updateTarget(_ x: CGFloat) {
        self.targetX = x
        if self.isTracking {
            self.currentX = x
            self.currentVelocity = 0
            let frame = CGRect(
                origin: CGPoint(x: self.currentX, y: self.frameTemplate.origin.y),
                size: self.frameTemplate.size
            )
            self.onFrameChanged?(frame)
        } else if self.displayLink == nil {
            self.startDisplayLink()
        }
    }

    func addVelocity(_ velocity: CGFloat) {
        self.currentVelocity += velocity
        self.isTracking = false
        if self.displayLink == nil {
            self.startDisplayLink()
        }
    }

    func stop() {
        self.stopDisplayLink()
        self.isTracking = false
    }

    private func startDisplayLink() {
        guard self.displayLink == nil else { return }

        self.displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max) { [weak self] dt in
            self?.tick(dt: dt)
        }
        self.displayLink?.isPaused = false
    }

    private func stopDisplayLink() {
        self.displayLink?.isPaused = true
        self.displayLink?.invalidate()
        self.displayLink = nil
    }

    private func tick(dt: CGFloat) {
        let clampedDt = min(dt, 1.0 / 30.0)

        let displacement = self.currentX - self.targetX
        let springForce = -self.stiffness * displacement
        let dampingForce = -self.damping * self.currentVelocity
        let acceleration = (springForce + dampingForce) / self.mass

        self.currentVelocity += acceleration * clampedDt
        self.currentX += self.currentVelocity * clampedDt

        let frame = CGRect(
            origin: CGPoint(x: self.currentX, y: self.frameTemplate.origin.y),
            size: self.frameTemplate.size
        )
        self.onFrameChanged?(frame)

        let velocityMagnitude = abs(self.currentVelocity)
        let distanceToTarget = abs(displacement)

        if velocityMagnitude < self.velocityThreshold && distanceToTarget < self.positionThreshold {
            self.currentX = self.targetX
            self.currentVelocity = 0
            self.isTracking = true
            let finalFrame = CGRect(
                origin: CGPoint(x: self.currentX, y: self.frameTemplate.origin.y),
                size: self.frameTemplate.size
            )
            self.onFrameChanged?(finalFrame)
            self.stopDisplayLink()
            self.onAnimationCompleted?()
        }
    }

    deinit {
        self.stopDisplayLink()
    }
}