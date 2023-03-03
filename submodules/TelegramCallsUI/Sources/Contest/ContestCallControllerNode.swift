import Foundation
import UIKit
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPreferences
import TelegramAudio
import AccountContext
import LocalizedPeerData
import PhotoResources
import CallsEmoji
import TooltipUI
import AlertUI
import PresentationDataUtils
import DeviceAccess
import ContextUI
import GradientBackground
import GraphCore
import AudioBlob
import EmojiTextAttachmentView
import ComponentFlow
import AvatarNode
import AnimatedAvatarSetNode

func ddlog(_ what: @autoclosure () -> String) {
    Logger.shared.log("ContestCalls", what())
}

private let defaultAudioLevel: Float = 0.45
private let avatarSize: CGSize = CGSize(width: 136.0, height: 136.0)
private let avatarFont = avatarPlaceholderFont(size: 48.0)
private let white = UIColor(rgb: 0xffffff)
private let initiatingGradients: [UIColor] = [UIColor(hexString: "#5295D6"), UIColor(hexString: "#616AD5"), UIColor(hexString: "#AC65D4"), UIColor(hexString: "#7261DA")].compactMap { $0 }
private let weakSignalGradients: [UIColor] = [UIColor(hexString: "#B84498"), UIColor(hexString: "#F4992E"), UIColor(hexString: "#C94986"), UIColor(hexString: "#FF7E46")].compactMap { $0 }
private let establishedGradients: [UIColor] = [UIColor(hexString: "#53A6DE"), UIColor(hexString: "#398D6F"), UIColor(hexString: "#BAC05D"), UIColor(hexString: "#3C9C8F")].compactMap { $0 }

private func interpolateFrame(from fromValue: CGRect, to toValue: CGRect, t: CGFloat) -> CGRect {
    return CGRect(x: floorToScreenPixels(toValue.origin.x * t + fromValue.origin.x * (1.0 - t)), y: floorToScreenPixels(toValue.origin.y * t + fromValue.origin.y * (1.0 - t)), width: floorToScreenPixels(toValue.size.width * t + fromValue.size.width * (1.0 - t)), height: floorToScreenPixels(toValue.size.height * t + fromValue.size.height * (1.0 - t)))
}

private func makeVisualEffectForGradient() -> UIVisualEffectView {
    let view: UIVisualEffectView
    if #available(iOS 13.0, *) {
        view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialLight))
    } else {
        view = UIVisualEffectView(effect: UIBlurEffect(style: .light))
    }
    view.alpha = 0.3
    return view
}

private func interpolate(from: CGFloat, to: CGFloat, value: CGFloat) -> CGFloat {
    return (1.0 - value) * from + value * to
}

protocol CallControllerButtonsNodeProtocol: ASDisplayNode {
    var isMuted: Bool { get set }
    
    var acceptOrEnd: (() -> Void)? { get set }
    var decline: (() -> Void)? { get set }
    var mute: (() -> Void)? { get set }
    var speaker: (() -> Void)? { get set }
    var toggleVideo: (() -> Void)? { get set }
    var rotateCamera: (() -> Void)? { get set }
    
    func videoButtonFrame() -> CGRect?
    func updateLayout(strings: PresentationStrings, mode: CallControllerButtonsMode, constrainedWidth: CGFloat, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGFloat
}

final class ContestCallControllerNode: ViewControllerTracingNode, CallControllerNodeProtocol {
    private enum VideoNodeCorner {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }
    
    private let sharedContext: SharedAccountContext
    private let accountContext: AccountContext
    private let account: Account
    
    private let statusBar: StatusBar
    
    private var presentationData: PresentationData
    private var peer: Peer?
    private let debugInfo: Signal<(String, String), NoError>
    private var forceReportRating = false
    private let easyDebugAccess: Bool
    private let call: PresentationCall
    
    private let containerTransformationNode: ASDisplayNode
    private let containerNode: ASDisplayNode
    private let videoContainerNode: PinchSourceContainerNode
    
    private let avatarNode: ContestCallAvatarNode
    private var avatarNodeAnimationInProgress = false
    
    private var candidateIncomingVideoNodeValue: CallVideoNode?
    private var incomingVideoNodeValue: CallVideoNode?
    private var incomingVideoViewRequested: Bool = false
    private var candidateOutgoingVideoNodeValue: CallVideoNode?
    private var outgoingVideoNodeValue: CallVideoNode?
    private var previewOutgoingVideoView: PresentationCallVideoView?
    private var outgoingVideoViewRequested: Bool = false
    private var fullScreenEffectView: UIVisualEffectView?
    
    private var removedMinimizedVideoNodeValue: CallVideoNode?
    private var removedExpandedVideoNodeValue: CallVideoNode?
    private var removedExpandedVideoNodeValueIsIncoming: Bool?
    
    private var isRequestingVideo: Bool = false
    private var animateRequestedVideoOnce: Bool = false
    
    private var hiddenUIForActiveVideoCallOnce: Bool = false
    private var hideUIForActiveVideoCallTimer: SwiftSignalKit.Timer?
    
    private var displayedCameraConfirmation: Bool = false
    private var displayedCameraTooltip: Bool = false
    
    private var expandedVideoNode: CallVideoNode?{
        didSet {
            updateBlurForSubnode()
        }
    }
    private var minimizedVideoNode: CallVideoNode? {
        didSet {
            updateBlurForSubnode()
        }
    }
    private var disableAnimationForExpandedVideoOnce: Bool = false
    private var animationForExpandedVideoSnapshotView: UIView? = nil
    private var animationForMinimizedVideoSnapshotView: UIView? = nil
    
    private var outgoingVideoNodeCorner: VideoNodeCorner = .bottomRight
    private let backButtonArrowNode: ASImageNode
    private let backButtonNode: HighlightableButtonNode
    private let statusNode: ContestCallControllerStatusNode
    private let toastNode: ContestCallControllerToastContainerNode
    private let buttonsNode: ContestCallControllerButtonsNode
    private var keyPreviewNode: ContestCallControllerKeyPreviewNode?
    private var ratingCallNode: ContestCallRatingNode?
    
    private var debugNode: CallDebugNode?
    
    private var keyTextData: (Data, String)?
    private let keyButtonNode: ContestCallControllerKeyButton
    
    private var validLayout: (ContainerViewLayout, CGFloat)?
    private var disableActionsUntilTimestamp: Double = 0.0
    
    private var displayedVersionOutdatedAlert: Bool = false
    
    var isMuted: Bool = false {
        didSet {
            self.buttonsNode.isMuted = self.isMuted
            self.updateToastContent()
            if let (layout, navigationBarHeight) = self.validLayout {
                self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
            }
        }
    }
    var canShowEncryptionTooltip: Bool = false
    var encryptionTooltipDismissed: (() -> Void)?

    private var shouldStayHiddenUntilConnection: Bool = false
    
    private var audioOutputState: ([AudioSessionOutput], currentOutput: AudioSessionOutput?)?
    private var callState: PresentationCallState?
    
    var ratingSelected: ((RatingSelectedItem) -> Void)?
    var ratingDissmiss: (() -> Void)?
    
    var toggleMute: (() -> Void)?
    var setCurrentAudioOutput: ((AudioSessionOutput) -> Void)?
    var beginAudioOuputSelection: ((Bool) -> Void)?
    var acceptCall: (() -> Void)?
    var endCall: (() -> Void)?
    var back: (() -> Void)?
    var presentCallRating: ((CallId, Bool) -> Void)?
    var callEnded: ((Bool) -> Void)?
    var dismissedInteractively: (() -> Void)?
    var present: ((ViewController) -> Void)?
    var dismissAllTooltips: (() -> Void)?

    private var toastContent: CallControllerToastContent?
    private var displayToastsAfterTimestamp: Double?
    
    private var buttonsMode: CallControllerButtonsMode?
    
    private var isUIHidden: Bool = false
    private var isVideoPaused: Bool = false
    private var isVideoPinched: Bool = false
    
    private enum PictureInPictureGestureState {
        case none
        case collapsing(didSelectCorner: Bool)
        case dragging(initialPosition: CGPoint, draggingPosition: CGPoint)
    }
    
    private var pictureInPictureGestureState: PictureInPictureGestureState = .none
    private var pictureInPictureCorner: VideoNodeCorner = .topRight
    private var pictureInPictureTransitionFraction: CGFloat = 0.0
    
    private var deviceOrientation: UIDeviceOrientation = .portrait
    private var orientationDidChangeObserver: NSObjectProtocol?
    
    private var currentRequestedAspect: CGFloat?
    
    private var stopInteractiveUITimer: SwiftSignalKit.Timer?
    private var gradientBackgroundNode: GradientBackgroundNode?
    private var gradientEffectView: UIVisualEffectView?
    private var activeGradientColors: [UIColor] = []
    private var gradientAnimationEnabled = false
    private let speakingContainerNode: ASDisplayNode
    private var onEstablishedAnimationAppeared = false
    private var audioLevelViewAnimationInProgress = false
    
    init(accountContext: AccountContext, sharedContext: SharedAccountContext, account: Account, presentationData: PresentationData, statusBar: StatusBar, debugInfo: Signal<(String, String), NoError>, shouldStayHiddenUntilConnection: Bool = false, easyDebugAccess: Bool, call: PresentationCall) {
        self.accountContext = accountContext
        self.sharedContext = sharedContext
        self.account = account
        self.presentationData = presentationData
        self.statusBar = statusBar
        self.debugInfo = debugInfo
        self.shouldStayHiddenUntilConnection = shouldStayHiddenUntilConnection
        self.easyDebugAccess = easyDebugAccess
        self.call = call
        
        self.containerTransformationNode = ASDisplayNode()
        self.containerTransformationNode.clipsToBounds = true
        
        self.containerNode = ASDisplayNode()
        
        self.videoContainerNode = PinchSourceContainerNode()
        
        self.avatarNode = ContestCallAvatarNode(size: avatarSize, avatarFont: avatarFont)

        self.backButtonArrowNode = ASImageNode()
        self.backButtonArrowNode.displayWithoutProcessing = true
        self.backButtonArrowNode.displaysAsynchronously = false
        self.backButtonArrowNode.image = NavigationBarTheme.generateBackArrowImage(color: .white)
        self.backButtonArrowNode.alpha = 0.0
        self.backButtonNode = HighlightableButtonNode()
        self.backButtonNode.alpha = 0.0
        
        self.statusNode = ContestCallControllerStatusNode(weakNetworkText: presentationData.strings.Calls_ContestWeakNetwork)
        
        self.gradientBackgroundNode = createGradientBackgroundNode(colors: initiatingGradients)
        self.gradientEffectView = makeVisualEffectForGradient()
        
        self.speakingContainerNode = ASDisplayNode()
        self.buttonsNode = ContestCallControllerButtonsNode(strings: self.presentationData.strings)
        self.toastNode = ContestCallControllerToastContainerNode(strings: self.presentationData.strings, light: true)
        self.keyButtonNode = ContestCallControllerKeyButton()
        self.keyButtonNode.accessibilityElementsHidden = false
        
        super.init()
        
        self.containerNode.backgroundColor = .black
        
        self.addSubnode(self.containerTransformationNode)
        self.containerTransformationNode.addSubnode(self.containerNode)
        
        self.backButtonNode.setTitle(presentationData.strings.Common_Back, with: Font.regular(17.0), with: .white, for: [])
        self.backButtonNode.accessibilityLabel = presentationData.strings.Call_VoiceOver_Minimize
        self.backButtonNode.accessibilityTraits = [.button]
        self.backButtonNode.hitTestSlop = UIEdgeInsets(top: -8.0, left: -20.0, bottom: -8.0, right: -8.0)
        self.backButtonNode.highligthedChanged = { [weak self] highlighted in
            if let strongSelf = self {
                if highlighted {
                    strongSelf.backButtonNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.backButtonArrowNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.backButtonNode.alpha = 0.4
                    strongSelf.backButtonArrowNode.alpha = 0.4
                } else {
                    strongSelf.backButtonNode.alpha = 1.0
                    strongSelf.backButtonArrowNode.alpha = 1.0
                    strongSelf.backButtonNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                    strongSelf.backButtonArrowNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                }
            }
        }
        
        self.gradientBackgroundNode.map(self.containerNode.addSubnode)
        if let effect = self.gradientEffectView {
            self.gradientBackgroundNode?.view.addSubview(effect)
        }
        
        self.speakingContainerNode.addSubnode(self.avatarNode)
        self.containerNode.addSubnode(self.speakingContainerNode)
        self.containerNode.addSubnode(self.videoContainerNode)
        
        self.containerNode.addSubnode(self.statusNode)
        self.containerNode.addSubnode(self.buttonsNode)
        self.containerNode.addSubnode(self.toastNode)
        self.containerNode.addSubnode(self.keyButtonNode)
        self.containerNode.addSubnode(self.backButtonArrowNode)
        self.containerNode.addSubnode(self.backButtonNode)
        
        self.buttonsNode.mute = { [weak self] in
            self?.toggleMute?()
            self?.cancelScheduledUIHiding()
        }
        
        self.buttonsNode.speaker = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.beginAudioOuputSelection?(strongSelf.hasVideoNodes)
            strongSelf.cancelScheduledUIHiding()
        }
                
        self.buttonsNode.acceptOrEnd = { [weak self] in
            guard let strongSelf = self, let callState = strongSelf.callState else {
                return
            }
            switch callState.state {
            case .active, .connecting, .reconnecting:
                strongSelf.endCall?()
                strongSelf.cancelScheduledUIHiding()
            case .requesting:
                strongSelf.endCall?()
            case .ringing:
                strongSelf.acceptCall?()
            default:
                break
            }
        }
        
        self.buttonsNode.decline = { [weak self] in
            self?.endCall?()
        }
        
        self.buttonsNode.toggleVideo = { [weak self] in
            guard let strongSelf = self, let callState = strongSelf.callState else {
                return
            }
            switch callState.state {
            case .active:
                var isScreencastActive = false
                switch callState.videoState {
                case .active(true), .paused(true):
                    isScreencastActive = true
                default:
                    break
                }

                if isScreencastActive {
                    (strongSelf.call as! PresentationCallImpl).disableScreencast()
                } else if strongSelf.outgoingVideoNodeValue == nil {
                    DeviceAccess.authorizeAccess(to: .camera(.videoCall), onlyCheck: true, presentationData: strongSelf.presentationData, present: { [weak self] c, a in
                        if let strongSelf = self {
                            strongSelf.present?(c)
                        }
                    }, openSettings: { [weak self] in
                        self?.sharedContext.applicationBindings.openSettings()
                    }, _: { [weak self] ready in
                        guard let strongSelf = self, ready else {
                            return
                        }
                        let proceed = {
                            strongSelf.displayedCameraConfirmation = true
                            switch callState.videoState {
                            case .inactive:
                                strongSelf.isRequestingVideo = true
                                strongSelf.updateButtonsMode()
                            default:
                                break
                            }
                            strongSelf.call.requestVideo()
                        }
                        
                        strongSelf.call.makeOutgoingVideoView(completion: { [weak self] outgoingVideoView in
                            guard let strongSelf = self else {
                                return
                            }
                            strongSelf.previewOutgoingVideoView = outgoingVideoView
                            if let outgoingVideoView = outgoingVideoView {
                                outgoingVideoView.view.backgroundColor = .black
                                outgoingVideoView.view.clipsToBounds = true
                                
                                var updateLayoutImpl: ((ContainerViewLayout, CGFloat) -> Void)?
                                
                                let outgoingVideoNode = CallVideoNode(videoView: outgoingVideoView, disabledText: nil, assumeReadyAfterTimeout: true, isReadyUpdated: {
                                    guard let strongSelf = self, let (layout, navigationBarHeight) = strongSelf.validLayout else {
                                        return
                                    }
                                    updateLayoutImpl?(layout, navigationBarHeight)
                                }, orientationUpdated: {
                                    guard let strongSelf = self, let (layout, navigationBarHeight) = strongSelf.validLayout else {
                                        return
                                    }
                                    updateLayoutImpl?(layout, navigationBarHeight)
                                }, isFlippedUpdated: { _ in
                                    guard let strongSelf = self, let (layout, navigationBarHeight) = strongSelf.validLayout else {
                                        return
                                    }
                                    updateLayoutImpl?(layout, navigationBarHeight)
                                })
                                
                                let fromFrame = strongSelf.buttonsNode.videoButtonFrame().flatMap({ frame in
                                    strongSelf.buttonsNode.view.convert(frame, to: strongSelf.view)
                                })
                                let controller = ContestVoiceChatCameraPreviewController(sharedContext: strongSelf.sharedContext, cameraNode: outgoingVideoNode, fromFrame: fromFrame, shareCamera: { _, _ in
                                    proceed()
                                }, switchCamera: { [weak self] in
                                    Queue.mainQueue().after(0.1) {
                                        self?.call.switchVideoCamera()
                                    }
                                })
                                strongSelf.present?(controller)
                                
                                updateLayoutImpl = { [weak controller] layout, navigationBarHeight in
                                    controller?.containerLayoutUpdated(layout, transition: .immediate)
                                }
                            }
                        })
                    })
                } else {
                    strongSelf.call.disableVideo()
                    strongSelf.cancelScheduledUIHiding()
                }
            default:
                break
            }
        }
        
        self.buttonsNode.rotateCamera = { [weak self] in
            guard let strongSelf = self, !strongSelf.areUserActionsDisabledNow() else {
                return
            }
            strongSelf.disableActionsUntilTimestamp = CACurrentMediaTime() + 1.0
            if let outgoingVideoNode = strongSelf.outgoingVideoNodeValue {
                outgoingVideoNode.flip(withBackground: outgoingVideoNode !== strongSelf.minimizedVideoNode)
            }
            strongSelf.call.switchVideoCamera()
            if let _ = strongSelf.outgoingVideoNodeValue {
                if let (layout, navigationBarHeight) = strongSelf.validLayout {
                    strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
                }
            }
            strongSelf.cancelScheduledUIHiding()
        }
        
        self.keyButtonNode.addTarget(self, action: #selector(self.keyPressed), forControlEvents: .touchUpInside)
        
        self.backButtonNode.addTarget(self, action: #selector(self.backPressed), forControlEvents: .touchUpInside)
        
        if shouldStayHiddenUntilConnection {
            self.containerNode.alpha = 0.0
            Queue.mainQueue().after(3.0, { [weak self] in
                self?.containerNode.alpha = 1.0
                self?.animateIn()
            })
        } else if call.isVideo && call.isOutgoing {
            self.containerNode.alpha = 0.0
            Queue.mainQueue().after(1.0, { [weak self] in
                self?.containerNode.alpha = 1.0
                self?.animateIn()
            })
        }
        
        self.orientationDidChangeObserver = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: nil, using: { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
            let deviceOrientation = UIDevice.current.orientation
            if strongSelf.deviceOrientation != deviceOrientation {
                strongSelf.deviceOrientation = deviceOrientation
                if let (layout, navigationBarHeight) = strongSelf.validLayout {
                    strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                }
            }
        })
        
        self.videoContainerNode.activate = { [weak self] sourceNode in
            guard let strongSelf = self else {
                return
            }
            let pinchController = PinchController(sourceNode: sourceNode, getContentAreaInScreenSpace: {
                return UIScreen.main.bounds
            })
            strongSelf.sharedContext.mainWindow?.presentInGlobalOverlay(pinchController)
            strongSelf.isVideoPinched = true
            
            strongSelf.videoContainerNode.contentNode.clipsToBounds = true
            strongSelf.videoContainerNode.backgroundColor = .red
            
            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                strongSelf.videoContainerNode.contentNode.cornerRadius = layout.deviceMetrics.screenCornerRadius
                
                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
            }
        }
        
        self.videoContainerNode.animatedOut = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isVideoPinched = false
            
            strongSelf.videoContainerNode.backgroundColor = .clear
            strongSelf.videoContainerNode.contentNode.cornerRadius = 0.0
            
            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
            }
        }
    }
    
    deinit {
        if let orientationDidChangeObserver = self.orientationDidChangeObserver {
            NotificationCenter.default.removeObserver(orientationDidChangeObserver)
        }
    }
    
    func displayCameraTooltip() {
        guard self.pictureInPictureTransitionFraction.isZero, let location = self.buttonsNode.videoButtonFrame().flatMap({ frame -> CGRect in
            return self.buttonsNode.view.convert(frame, to: self.view)
        }) else {
            return
        }
                
        self.present?(TooltipScreen(account: self.account, text: self.presentationData.strings.Call_CameraOrScreenTooltip, style: .light, icon: nil, location: .point(location.offsetBy(dx: 0.0, dy: -14.0), .bottom), displayDuration: .custom(5.0), shouldDismissOnTouch: { _ in
            return .dismiss(consume: false)
        }))
    }
    
    func displayEncriptionTooltip() {
        guard self.pictureInPictureTransitionFraction.isZero, self.canShowEncryptionTooltip else {
            return
        }
        let location = self.keyButtonNode.frame
        let text = self.presentationData.strings.Calls_ContestKeyEncripted
        self.present?(TooltipScreen(account: self.account, text: text, style: .custom(fontSize: 15.0, contentInset: UIEdgeInsets(top: 9.0, left: 16.0, bottom: 9.0, right: 16.0), backgroundColor: self.hasVideoNodes ? UIColor.black.withAlphaComponent(0.7) : UIColor.white.withAlphaComponent(0.25)), icon: .callsEncrypted, location: .point(location.offsetBy(dx: 0.0, dy: +8.0), .top), displayDuration: .custom(4.0), shouldDismissOnTouch: { [weak self] point in
            guard let strongSelf = self else {
                return .ignore
            }
            if strongSelf.keyButtonNode.frame.contains(point) {
                strongSelf.encryptionTooltipDismissed?()
                return .dismiss(consume: false)
            } else {
                return .ignore
            }
        }))
    }
    
    override func didLoad() {
        super.didLoad()
        
        let panRecognizer = CallPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:)))
        panRecognizer.shouldBegin = { [weak self] _ in
            guard let strongSelf = self else {
                return false
            }
            if strongSelf.areUserActionsDisabledNow() {
                return false
            }
            return true
        }
        self.view.addGestureRecognizer(panRecognizer)
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:)))
        self.view.addGestureRecognizer(tapRecognizer)
    }
    
    func updatePeer(accountPeer: Peer, peer: Peer, hasOther: Bool) {
        if !arePeersEqual(self.peer, peer) {
            self.peer = peer
            self.avatarNode.setPeer(context: self.accountContext, peer: EnginePeer(peer), synchronousLoad: true, placeholderColor: self.presentationData.theme.list.mediaPlaceholderColor)
            self.toastNode.title = EnginePeer(peer).compactDisplayTitle
            self.statusNode.title = EnginePeer(peer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)
            if hasOther {
                self.statusNode.subtitle = self.presentationData.strings.Call_AnsweringWithAccount(EnginePeer(accountPeer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)).string
                
                if let callState = self.callState {
                    self.updateCallState(callState)
                }
            }
            
            if let (layout, navigationBarHeight) = self.validLayout {
                self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
            }
        }
    }
    
    func updateAudioOutputs(availableOutputs: [AudioSessionOutput], currentOutput: AudioSessionOutput?) {
        if self.audioOutputState?.0 != availableOutputs || self.audioOutputState?.1 != currentOutput {
            self.audioOutputState = (availableOutputs, currentOutput)
            self.updateButtonsMode()
            
            self.setupAudioOutputs()
        }
    }
    
    private func setupAudioOutputs() {
        if self.outgoingVideoNodeValue != nil || self.incomingVideoNodeValue != nil || self.candidateOutgoingVideoNodeValue != nil || self.candidateIncomingVideoNodeValue != nil {
            if let audioOutputState = self.audioOutputState, let currentOutput = audioOutputState.currentOutput {
                switch currentOutput {
                case .headphones, .speaker:
                    break
                case let .port(port) where port.type == .bluetooth || port.type == .wired:
                    break
                default:
                    self.setCurrentAudioOutput?(.speaker)
                }
            }
        }
    }
    
    func updateCallState(_ callState: PresentationCallState) {
        self.callState = callState
        
        var statusTitle: String? = nil
        let statusValue: ContestCallControllerStatusValue
        var statusReception: Int32?
        
        switch callState.remoteVideoState {
        case .active, .paused:
            if !self.incomingVideoViewRequested {
                self.incomingVideoViewRequested = true
                let delayUntilInitialized = true
                self.call.makeIncomingVideoView(completion: { [weak self] incomingVideoView in
                    guard let strongSelf = self else {
                        return
                    }
                    if let incomingVideoView = incomingVideoView {
                        incomingVideoView.view.backgroundColor = .black
                        incomingVideoView.view.clipsToBounds = true
                        
                        let applyNode: () -> Void = {
                            guard let strongSelf = self, let incomingVideoNode = strongSelf.candidateIncomingVideoNodeValue else {
                                return
                            }
                            strongSelf.candidateIncomingVideoNodeValue = nil
                            
                            strongSelf.incomingVideoNodeValue = incomingVideoNode
                            if let expandedVideoNode = strongSelf.expandedVideoNode {
                                strongSelf.minimizedVideoNode = expandedVideoNode
                                strongSelf.videoContainerNode.contentNode.insertSubnode(incomingVideoNode, belowSubnode: expandedVideoNode)
                            } else {
                                strongSelf.videoContainerNode.contentNode.addSubnode(incomingVideoNode)
                            }
                            strongSelf.expandedVideoNode = incomingVideoNode
                            strongSelf.updateButtonsMode(transition: .animated(duration: 0.4, curve: .spring))
                            
                            strongSelf.updateDimVisibility()
                            strongSelf.maybeScheduleUIHidingForActiveVideoCall()
                        }
                        
                        let incomingVideoNode = CallVideoNode(videoView: incomingVideoView, disabledText: strongSelf.presentationData.strings.Call_RemoteVideoPaused(strongSelf.peer.flatMap(EnginePeer.init)?.compactDisplayTitle ?? "").string, assumeReadyAfterTimeout: false, isReadyUpdated: {
                            if delayUntilInitialized {
                                Queue.mainQueue().after(0.1, {
                                    applyNode()
                                })
                            }
                        }, orientationUpdated: {
                            guard let strongSelf = self else {
                                return
                            }
                            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                            }
                        }, isFlippedUpdated: { _ in
                        })
                        strongSelf.candidateIncomingVideoNodeValue = incomingVideoNode
                        strongSelf.setupAudioOutputs()
                        
                        if !delayUntilInitialized {
                            applyNode()
                        }
                    }
                })
            }
        case .inactive:
            self.candidateIncomingVideoNodeValue = nil
            if let incomingVideoNodeValue = self.incomingVideoNodeValue {
                if self.minimizedVideoNode == incomingVideoNodeValue {
                    self.minimizedVideoNode = nil
                    self.removedMinimizedVideoNodeValue = incomingVideoNodeValue
                }
                if self.expandedVideoNode == incomingVideoNodeValue {
                    self.expandedVideoNode = nil
                    self.removedExpandedVideoNodeValue = incomingVideoNodeValue
                    self.removedExpandedVideoNodeValueIsIncoming = true
                    
                    if let minimizedVideoNode = self.minimizedVideoNode {
                        self.expandedVideoNode = minimizedVideoNode
                        self.minimizedVideoNode = nil
                    }
                }
                self.incomingVideoNodeValue = nil
                self.incomingVideoViewRequested = false
            }
        }
        
        switch callState.videoState {
        case .active(false), .paused(false):
            if !self.outgoingVideoViewRequested {
                self.outgoingVideoViewRequested = true
                let delayUntilInitialized = self.isRequestingVideo && self.previewOutgoingVideoView == nil
                
                let handleOutgoingVideoView: (PresentationCallVideoView?) -> Void = { [weak self] outgoingVideoView in
                    guard let strongSelf = self else {
                        return
                    }
                    
                    if let outgoingVideoView = outgoingVideoView {
                        outgoingVideoView.view.backgroundColor = .black
                        outgoingVideoView.view.clipsToBounds = true
                        
                        let applyNode: () -> Void = {
                            guard let strongSelf = self, let outgoingVideoNode = strongSelf.candidateOutgoingVideoNodeValue else {
                                return
                            }
                            strongSelf.candidateOutgoingVideoNodeValue = nil
                            
                            if strongSelf.isRequestingVideo {
                                strongSelf.isRequestingVideo = false
                                strongSelf.animateRequestedVideoOnce = true
                            }
                            
                            strongSelf.outgoingVideoNodeValue = outgoingVideoNode
                            if let expandedVideoNode = strongSelf.expandedVideoNode {
                                strongSelf.minimizedVideoNode = outgoingVideoNode
                                strongSelf.videoContainerNode.contentNode.insertSubnode(outgoingVideoNode, aboveSubnode: expandedVideoNode)
                            } else {
                                strongSelf.expandedVideoNode = outgoingVideoNode
                                strongSelf.videoContainerNode.contentNode.addSubnode(outgoingVideoNode)
                            }
                            strongSelf.updateButtonsMode(transition: .animated(duration: 0.4, curve: .spring))
                            
                            strongSelf.updateDimVisibility()
                            strongSelf.maybeScheduleUIHidingForActiveVideoCall()
                        }
                        
                        let outgoingVideoNode = CallVideoNode(videoView: outgoingVideoView, disabledText: nil, assumeReadyAfterTimeout: true, isReadyUpdated: {
                            if delayUntilInitialized {
                                Queue.mainQueue().after(0.4, {
                                    applyNode()
                                })
                            }
                        }, orientationUpdated: {
                            guard let strongSelf = self else {
                                return
                            }
                            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                            }
                        }, isFlippedUpdated: { videoNode in
                            guard let _ = self else {
                                return
                            }
                            /*if videoNode === strongSelf.minimizedVideoNode, let tempView = videoNode.view.snapshotView(afterScreenUpdates: true) {
                                videoNode.view.superview?.insertSubview(tempView, aboveSubview: videoNode.view)
                                videoNode.view.frame = videoNode.frame
                                let transitionOptions: UIView.AnimationOptions = [.transitionFlipFromRight, .showHideTransitionViews]

                                UIView.transition(with: tempView, duration: 1.0, options: transitionOptions, animations: {
                                    tempView.isHidden = true
                                }, completion: { [weak tempView] _ in
                                    tempView?.removeFromSuperview()
                                })

                                videoNode.view.isHidden = true
                                UIView.transition(with: videoNode.view, duration: 1.0, options: transitionOptions, animations: {
                                    videoNode.view.isHidden = false
                                })
                            }*/
                        })
                        
                        strongSelf.candidateOutgoingVideoNodeValue = outgoingVideoNode
                        strongSelf.setupAudioOutputs()
                        
                        if !delayUntilInitialized {
                            applyNode()
                        }
                    }
                }
                if let previewOutgoingVideoView = self.previewOutgoingVideoView {
                    handleOutgoingVideoView(previewOutgoingVideoView)
                    self.previewOutgoingVideoView = nil
                } else {
                    self.call.makeOutgoingVideoView(completion: handleOutgoingVideoView)
                }
            }
        default:
            self.candidateOutgoingVideoNodeValue = nil
            if let outgoingVideoNodeValue = self.outgoingVideoNodeValue {
                if self.minimizedVideoNode == outgoingVideoNodeValue {
                    self.minimizedVideoNode = nil
                    self.removedMinimizedVideoNodeValue = outgoingVideoNodeValue
                }
                if self.expandedVideoNode == self.outgoingVideoNodeValue {
                    self.expandedVideoNode = nil
                    self.removedExpandedVideoNodeValue = outgoingVideoNodeValue
                    self.removedExpandedVideoNodeValueIsIncoming = false
                    
                    if let minimizedVideoNode = self.minimizedVideoNode {
                        self.expandedVideoNode = minimizedVideoNode
                        self.minimizedVideoNode = nil
                    }
                }
                self.outgoingVideoNodeValue = nil
                self.outgoingVideoViewRequested = false
            }
        }
        
        var incomingVideoNodeBlurIsActive: Bool = false
        if let incomingVideoNode = self.incomingVideoNodeValue {
            switch callState.state {
            case .terminating, .terminated:
                break
            default:
                switch callState.remoteVideoState {
                case .inactive, .paused:
                    incomingVideoNodeBlurIsActive = false
                case .active:
                    incomingVideoNodeBlurIsActive = true
                }
                incomingVideoNode.updateIsBlurred(isBlurred: !incomingVideoNodeBlurIsActive)
            }
        }
                
        switch callState.state {
            case .waiting, .connecting:
                statusValue = .text(string: self.presentationData.strings.Call_StatusConnecting, image: nil)
            case let .requesting(ringing):
                if ringing {
                    statusValue = .text(string: self.presentationData.strings.Call_StatusRinging, image: nil)
                } else {
                    statusValue = .text(string: self.presentationData.strings.Call_StatusRequesting, image: nil)
                }
            case .terminating:
                self.updateGradient(colors: initiatingGradients)
                statusValue = .text(string: self.statusNode.lastPrintedTime, image: .callEnd)
                statusTitle = self.presentationData.strings.Call_StatusEnded
            case let .terminated(_, reason, _):
                self.updateGradient(colors: initiatingGradients)
                if let reason = reason {
                    switch reason {
                        case let .ended(type):
                            switch type {
                                case .busy:
                                    statusValue = .text(string: self.presentationData.strings.Call_StatusBusy, image: nil)
                                case .hungUp, .missed:
                                    statusTitle = self.presentationData.strings.Call_StatusEnded
                                    statusValue = .text(string: self.statusNode.lastPrintedTime, image: .callEnd)
                            }
                        case let .error(error):
                            let text = self.presentationData.strings.Call_StatusFailed
                            switch error {
                            case let .notSupportedByPeer(isVideo):
                                if !self.displayedVersionOutdatedAlert, let peer = self.peer {
                                    self.displayedVersionOutdatedAlert = true
                                    
                                    let text: String
                                    if isVideo {
                                        text = self.presentationData.strings.Call_ParticipantVideoVersionOutdatedError(EnginePeer(peer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)).string
                                    } else {
                                        text = self.presentationData.strings.Call_ParticipantVersionOutdatedError(EnginePeer(peer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)).string
                                    }
                                    
                                    self.present?(textAlertController(sharedContext: self.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {
                                    })]))
                                }
                            default:
                                break
                            }
                            statusValue = .text(string: text, image: nil)
                    }
                } else {
                    statusValue = .text(string: self.statusNode.lastPrintedTime, image: .callEnd)
                    statusTitle = self.presentationData.strings.Call_StatusEnded
                }
            case .ringing:
                var text: String
                if self.call.isVideo {
                    text = self.presentationData.strings.Call_IncomingVideoCall
                } else {
                    text = self.presentationData.strings.Call_IncomingVoiceCall
                }
                if !self.statusNode.subtitle.isEmpty {
                    text += "\n\(self.statusNode.subtitle)"
                }
                statusValue = .text(string: text, image: nil)
            case .active(let timestamp, let reception, let keyVisualHash), .reconnecting(let timestamp, let reception, let keyVisualHash):
                if self.keyTextData?.0 != keyVisualHash {
                    let text = stringForEmojiHashOfData(keyVisualHash, 4)!
                    self.keyTextData = (keyVisualHash, text)

                    self.keyButtonNode.key = text
                    self.prefetchKeyAnimationFiles(text)

                    let keyTextSize = self.keyButtonNode.measure(CGSize(width: 200.0, height: 200.0))
                    self.keyButtonNode.frame = CGRect(origin: self.keyButtonNode.frame.origin, size: keyTextSize)
                    
                    self.keyButtonNode.animateIn()
                    
                    if let (layout, navigationBarHeight) = self.validLayout {
                        self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
                    }

                    self.animateAvatarAndBackArrow()
                }

                statusValue = .timer({ value, measure in
                    return value
                }, timestamp)

                statusReception = reception
                if (reception ?? 100) <= 1 {
                    self.updateGradient(colors: weakSignalGradients)
                    self.incomingVideoNodeValue?.updateIsBlurred(isBlurred: true, reason: .weakNetwork, light: true)
                } else {
                    self.incomingVideoNodeValue?.updateIsBlurred(isBlurred: !incomingVideoNodeBlurIsActive, reason: .weakNetwork)
                    self.updateGradient(colors: establishedGradients)
                }
        }
        if self.shouldStayHiddenUntilConnection {
            switch callState.state {
                case .connecting, .active:
                    self.containerNode.alpha = 1.0
                default:
                    break
            }
        }
        if let statusTitle = statusTitle {
            self.statusNode.title = statusTitle
        }
        self.statusNode.status = statusValue
        self.statusNode.reception = statusReception
        
        if let callState = self.callState {
            switch callState.state {
            case .active, .connecting, .reconnecting:
                break
            default:
                self.isUIHidden = false
            }
        }
        
        if case let .terminated(id, _, reportRating) = callState.state, let callId = id {
            let presentRating = reportRating || self.forceReportRating
            if presentRating {
                self.showCallRating(callId, self.call.isVideo)
            }
            self.callEnded?(presentRating)
            self.dismissAllTooltips?()
        }

        self.updateToastContent()
        self.updateButtonsMode()
        self.updateDimVisibility()
        
        if self.incomingVideoViewRequested || self.outgoingVideoViewRequested {
            if self.incomingVideoViewRequested && self.outgoingVideoViewRequested {
                self.displayedCameraTooltip = true
            }
            self.displayedCameraConfirmation = true
        }
        if self.incomingVideoViewRequested && !self.outgoingVideoViewRequested && !self.displayedCameraTooltip && (self.toastContent?.isEmpty ?? true) {
            self.displayedCameraTooltip = true
            Queue.mainQueue().after(2.0) {
                self.displayCameraTooltip()
            }
        }
        
        let hasIncomingVideoNode = self.incomingVideoNodeValue != nil && self.expandedVideoNode === self.incomingVideoNodeValue
        self.videoContainerNode.isPinchGestureEnabled = hasIncomingVideoNode
    }
    
    private func showCallRating(_ callId: CallId, _ isVideo: Bool, transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .easeInOut)) {
        
        self.avatarNode.stopAnimating()
        
        let node = ContestCallRatingNode(strings: self.presentationData.strings, light: !self.hasVideoNodes, dismiss: { [weak self] in
            self?.ratingDissmiss?()
        }, apply: { [weak self] rating in
            self?.ratingSelected?(RatingSelectedItem(rating: rating, isVideo: isVideo, callId: callId))
        })
        self.addSubnode(node)
        
        self.ratingCallNode = node
        
        if let (layout, navigationHeight) = self.validLayout {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: transition)
        }
        if self.hasVideoNodes, self.isUIHidden {
            node.animateIn(buttonFrom: nil, buttonSnapshot: nil, transition: transition)
        } else {
            let (buttonFrame, snapshotView) = self.buttonsNode.endButton()
            let buttonFrom = buttonFrame.flatMap({ frame in
                self.buttonsNode.view.convert(frame, to: node.view)
            })
            node.animateIn(buttonFrom: buttonFrom, buttonSnapshot: snapshotView, transition: transition)
        }
    }
    
    private var prefetchKeyAnimationDisposable: DisposableSet = DisposableSet()
    private func prefetchKeyAnimationFiles(_ text: String) {
        let files = text.compactMap({
            self.accountContext.animatedEmojiStickers["\($0)"]?.first?.file
        })
        guard files.count == text.count else {
            return
        }
        for file in files {
            let isTemplate = file.isCustomTemplateEmoji
            let fetchFile = animationCacheFetchFile(context: self.accountContext, userLocation: .other, userContentType: .sticker, resource: .media(media: .standalone(media: file), resource: file.resource), type: AnimationCacheAnimationType(file: file), keyframeOnly: true, customColor: isTemplate ? .white : nil)
                
            let loadDisposable = self.accountContext.animationCache.get(sourceId: file.resource.id.stringRepresentation, size: ContestCallControllerKeyPreviewNode.emojiSize, fetch: fetchFile).start()
            self.prefetchKeyAnimationDisposable.add(loadDisposable)
        }
    }
    
    private func animateAvatarAndBackArrow() {
        if self.onEstablishedAnimationAppeared { return }
        
        let transition = ContainedViewLayoutTransition.animated(duration: 0.3, curve: .slide)
        
        self.onEstablishedAnimationAppeared = true
        self.avatarNodeAnimationInProgress = true
        self.avatarNode.animateInAndOut(completion: { [weak self] in
            self?.avatarNodeAnimationInProgress = false
        })

        let offset: CGFloat = 120.0
        var arrowFrom = self.backButtonArrowNode.frame
        arrowFrom.origin.x += offset
        transition.animateFrame(node: self.backButtonArrowNode, from: arrowFrom, to: self.backButtonArrowNode.frame)
        transition.updateAlpha(node: self.backButtonArrowNode, alpha: 1.0)

        var textFrom = self.backButtonNode.frame
        textFrom.origin.x += offset
        transition.animateFrame(node: self.backButtonNode, from: textFrom, to: self.backButtonNode.frame)
        transition.updateAlpha(node: self.backButtonNode, alpha: 1.0)
        
        Queue.mainQueue().after(0.5) { [weak self] in
            self?.displayEncriptionTooltip()
        }
    }
    
    private func updateGradient(colors: [UIColor]) {
        guard let gradientBackgroundNode = self.gradientBackgroundNode else {
            return
        }
        var updated = false
        if self.activeGradientColors.count != colors.count {
            updated = true
        } else {
            for i in 0 ..< self.activeGradientColors.count {
                if !self.activeGradientColors[i].isEqual(colors[i]) {
                    updated = true
                    break
                }
            }
        }
        guard updated else {
            return
        }
        self.activeGradientColors = colors
        
        let transition = ContainedViewLayoutTransition.animated(duration: 0.3, curve: .linear)
        let toRemoveGradientBackgroundNode = gradientBackgroundNode
        
        let updatedGradientBackgroundNode = createGradientBackgroundNode(colors: colors)
        let effect = makeVisualEffectForGradient()
        updatedGradientBackgroundNode.view.addSubview(effect)
        updatedGradientBackgroundNode.frame = gradientBackgroundNode.frame
        effect.frame = updatedGradientBackgroundNode.bounds
        updatedGradientBackgroundNode.alpha = 1.0
        updatedGradientBackgroundNode.updateLayout(size: gradientBackgroundNode.frame.size, transition: .immediate, extendAnimation: false, backwards: false, completion: {})
        self.containerNode.insertSubnode(updatedGradientBackgroundNode, belowSubnode: toRemoveGradientBackgroundNode)
        
        self.gradientBackgroundNode = updatedGradientBackgroundNode
        
        transition.updateAlpha(node: toRemoveGradientBackgroundNode, alpha: 0.0, completion: { [weak self, weak toRemoveGradientBackgroundNode, weak updatedGradientBackgroundNode] _ in
            toRemoveGradientBackgroundNode?.removeFromSupernode()
            self?.gradientBackgroundNode = updatedGradientBackgroundNode
        })
    }

    private func updateToastContent() {
        guard let callState = self.callState else {
            return
        }
        
        if case .terminating = callState.state {
            self.toastContent = []
        } else if case .terminated = callState.state {
            self.toastContent = []
        } else {
            var toastContent: CallControllerToastContent = []
            if case .active = callState.state {
                if let displayToastsAfterTimestamp = self.displayToastsAfterTimestamp {
                    if CACurrentMediaTime() > displayToastsAfterTimestamp {
                        if case .inactive = callState.remoteVideoState, self.hasVideoNodes {
                            toastContent.insert(.camera)
                        }
                        if case .muted = callState.remoteAudioState {
                            toastContent.insert(.microphone)
                        }
                        if case .low = callState.remoteBatteryLevel {
                            toastContent.insert(.battery)
                        }
                    }
                } else {
                    self.displayToastsAfterTimestamp = CACurrentMediaTime() + 1.5
                }
            }
            if self.isMuted {
                toastContent.insert(.mute)
            }
            self.toastContent = toastContent
        }
    }
    
    private func updateDimVisibility(transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .easeInOut)) {
//        guard self.incomingVideoNodeValue != nil else {
//            return
//        }
//        let toPosition = CGPoint(x: self.statusNode.position.x, y: self.backButtonNode.position.y)
//        transition.animatePosition(node: self.statusNode, to: toPosition)
//        transition.updateTransformScale(node: self.statusNode, scale: 0.5)
        
//        guard let callState = self.callState else {
//            return
//        }

        
//        var visible = true
//        if case .active = callState.state, self.incomingVideoNodeValue != nil || self.outgoingVideoNodeValue != nil {
//            visible = false
//        }
//
//        let currentVisible = self.dimNode.image == nil
//        if visible != currentVisible {
//            let color = visible ? UIColor(rgb: 0x000000, alpha: 0.3) : UIColor.clear
//            let image: UIImage? = visible ? nil : generateGradientImage(size: CGSize(width: 1.0, height: 640.0), colors: [UIColor.black.withAlphaComponent(0.3), UIColor.clear, UIColor.clear, UIColor.black.withAlphaComponent(0.3)], locations: [0.0, 0.22, 0.7, 1.0])
//            if case let .animated(duration, _) = transition {
//                UIView.transition(with: self.dimNode.view, duration: duration, options: .transitionCrossDissolve, animations: {
//                    self.dimNode.backgroundColor = color
//                    self.dimNode.image = image
//                }, completion: nil)
//            } else {
//                self.dimNode.backgroundColor = color
//                self.dimNode.image = image
//            }
//        }
//        self.statusNode.setVisible(visible || self.keyPreviewNode != nil, transition: transition)
    }
    
    private func maybeScheduleUIHidingForActiveVideoCall() {
        guard let callState = self.callState, case .active = callState.state, self.incomingVideoNodeValue != nil && self.outgoingVideoNodeValue != nil, !self.hiddenUIForActiveVideoCallOnce && self.keyPreviewNode == nil else {
            return
        }
        
        let timer = SwiftSignalKit.Timer(timeout: 3.0, repeat: false, completion: { [weak self] in
            if let strongSelf = self {
                var updated = false
                if let callState = strongSelf.callState, !strongSelf.isUIHidden {
                    switch callState.state {
                        case .active, .connecting, .reconnecting:
                            strongSelf.isUIHidden = true
                            updated = true
                        default:
                            break
                    }
                }
                if updated, let (layout, navigationBarHeight) = strongSelf.validLayout {
                    strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                }
                strongSelf.hideUIForActiveVideoCallTimer = nil
            }
        }, queue: Queue.mainQueue())
        timer.start()
        self.hideUIForActiveVideoCallTimer = timer
        self.hiddenUIForActiveVideoCallOnce = true
    }
    
    private func cancelScheduledUIHiding() {
        self.hideUIForActiveVideoCallTimer?.invalidate()
        self.hideUIForActiveVideoCallTimer = nil
    }
    
    private var buttonsTerminationMode: CallControllerButtonsMode?
    
    private func updateButtonsMode(transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .spring)) {
        guard let callState = self.callState else {
            return
        }
        
        var mode: CallControllerButtonsSpeakerMode = .none
        var hasAudioRouteMenu: Bool = false
        if let (availableOutputs, maybeCurrentOutput) = self.audioOutputState, let currentOutput = maybeCurrentOutput {
            hasAudioRouteMenu = availableOutputs.count > 2
            switch currentOutput {
                case .builtin:
                    mode = .builtin
                case .speaker:
                    mode = .speaker
                case .headphones:
                    mode = .headphones
                case let .port(port):
                    var type: CallControllerButtonsSpeakerMode.BluetoothType = .generic
                    let portName = port.name.lowercased()
                    if portName.contains("airpods pro") {
                        type = .airpodsPro
                    } else if portName.contains("airpods") {
                        type = .airpods
                    }
                    mode = .bluetooth(type)
            }
            if availableOutputs.count <= 1 {
                mode = .none
            }
        }
        var mappedVideoState = CallControllerButtonsMode.VideoState(isAvailable: false, isCameraActive: self.outgoingVideoNodeValue != nil, isScreencastActive: false, canChangeStatus: false, hasVideo: self.outgoingVideoNodeValue != nil || self.incomingVideoNodeValue != nil, isInitializingCamera: self.isRequestingVideo)
        switch callState.videoState {
        case .notAvailable:
            break
        case .inactive:
            mappedVideoState.isAvailable = true
            mappedVideoState.canChangeStatus = true
        case .active(let isScreencast), .paused(let isScreencast):
            mappedVideoState.isAvailable = true
            mappedVideoState.canChangeStatus = true
            if isScreencast {
                mappedVideoState.isScreencastActive = true
                mappedVideoState.hasVideo = true
            }
        }
        
        switch callState.state {
        case .ringing:
            self.buttonsMode = .incoming(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            self.buttonsTerminationMode = buttonsMode
        case .waiting, .requesting:
            self.buttonsMode = .outgoingRinging(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            self.buttonsTerminationMode = buttonsMode
        case .active, .connecting, .reconnecting:
            self.buttonsMode = .active(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            self.buttonsTerminationMode = buttonsMode
        case .terminating, .terminated:
            if let buttonsTerminationMode = self.buttonsTerminationMode {
                self.buttonsMode = buttonsTerminationMode
            } else {
                self.buttonsMode = .active(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            }
        }
                
        if let (layout, navigationHeight) = self.validLayout {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: transition)
        }
    }
    
    func animateIn() {
        if !self.containerNode.alpha.isZero {
            var bounds = self.bounds
            bounds.origin = CGPoint()
            self.bounds = bounds
            self.layer.removeAnimation(forKey: "bounds")
            self.statusBar.layer.removeAnimation(forKey: "opacity")
            self.containerNode.layer.removeAnimation(forKey: "opacity")
            self.containerNode.layer.removeAnimation(forKey: "scale")
            self.statusBar.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
            if !self.shouldStayHiddenUntilConnection {
                self.containerNode.layer.animateScale(from: 1.04, to: 1.0, duration: 0.3)
                self.containerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
            }
            
            self.startInteractiveUI()
        }
    }
    
    private var interactionInProgress = false

    func startInteractiveUI() {
        if self.hasVideoNodes || self.containerNode.alpha.isZero || self.avatarNode.frame.isEmpty || self.gradientBackgroundNode?.frame.isEmpty == true {
            return
        }
        self.scheduleStoInteractiveUI()
        if self.interactionInProgress {
            return
        }
        self.interactionInProgress = true
        self.gradientAnimationEnabled = true
        
        self.avatarNode.updateAudioLevel(color: .white, value: defaultAudioLevel)

        self.animateGradient()
    }
    
    func stopInteractiveUI() {
        guard self.interactionInProgress else {
            return
        }
        self.interactionInProgress = false
        self.gradientAnimationEnabled = false
        self.avatarNode.stopAnimating()
    }
    
    func setAudioLevel(_ level: Float) {
        guard self.interactionInProgress else {
            return
        }
        let level = max(level, defaultAudioLevel)
        self.avatarNode.updateAudioLevel(color: .white, value: level)
    }

    private func scheduleStoInteractiveUI() {
        self.stopInteractiveUITimer?.invalidate()
        self.stopInteractiveUITimer = SwiftSignalKit.Timer(timeout: 10.0, repeat: false, completion: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.stopInteractiveUI()

        }, queue: Queue.mainQueue())
        
        self.stopInteractiveUITimer?.start()
    }
    
    private func updateBlurForSubnode() {
        self.keyPreviewNode?.updateAppearance(light: !self.hasVideoNodes)
        self.toastNode.light = !self.hasVideoNodes
    }
    
    private func animateGradient() {
        guard self.gradientAnimationEnabled == true, self.gradientBackgroundNode?.isInDisplayState == true else {
            return
        }
        let startedDate = Date().timeIntervalSince1970
        self.gradientBackgroundNode?.animateEvent(transition: .animated(duration: 0.8, curve: .linear), extendAnimation: false, backwards: false, completion: { [weak self] in
            let finishedDate = Date().timeIntervalSince1970
            if (finishedDate - startedDate) < 0.7 {
                return
            }
            self?.animateGradient()
        })
    }
    
    func animateOut(completion: @escaping () -> Void) {
        self.stopInteractiveUI()
        
        self.statusBar.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false)
        if !self.shouldStayHiddenUntilConnection || self.containerNode.alpha > 0.0 {
            self.containerNode.layer.allowsGroupOpacity = true
            self.containerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { [weak self] _ in
                self?.containerNode.layer.allowsGroupOpacity = false
            })
            self.containerNode.layer.animateScale(from: 1.0, to: 1.04, duration: 0.3, removeOnCompletion: false, completion: { _ in
                completion()
            })
        } else {
            completion()
        }
    }
    
    func expandFromPipIfPossible() {
        if self.pictureInPictureTransitionFraction.isEqual(to: 1.0), let (layout, navigationHeight) = self.validLayout {
            self.pictureInPictureTransitionFraction = 0.0
            
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
        }
    }
    
    private func calculatePreviewVideoRect(layout: ContainerViewLayout, navigationHeight: CGFloat) -> CGRect {
        let buttonsHeight: CGFloat = self.buttonsNode.bounds.height
        let toastHeight: CGFloat = self.toastNode.bounds.height
        let toastInset = (toastHeight > 0.0 ? toastHeight + 16.0 : 0.0)
        
        var fullInsets = layout.insets(options: .statusBar)
    
        var cleanInsets = fullInsets
        cleanInsets.bottom = max(layout.intrinsicInsets.bottom, 16.0) + toastInset
        cleanInsets.left = 10.0
        cleanInsets.right = 10.0
        
        fullInsets.top += 44.0 + 8.0
        fullInsets.bottom = buttonsHeight + 16.0 + toastInset
        fullInsets.left = 10.0
        fullInsets.right = 10.0
        
        var insets: UIEdgeInsets = self.isUIHidden ? cleanInsets : fullInsets
        
        let expandedInset: CGFloat = 16.0
        
        insets.top = interpolate(from: expandedInset, to: insets.top, value: 1.0 - self.pictureInPictureTransitionFraction)
        insets.bottom = interpolate(from: expandedInset, to: insets.bottom, value: 1.0 - self.pictureInPictureTransitionFraction)
        insets.left = interpolate(from: expandedInset, to: insets.left, value: 1.0 - self.pictureInPictureTransitionFraction)
        insets.right = interpolate(from: expandedInset, to: insets.right, value: 1.0 - self.pictureInPictureTransitionFraction)
        
        let previewVideoSide: CGFloat
        if self.isUIHidden {
            previewVideoSide = interpolate(from: 300.0, to: 140.0, value: 1.0 - self.pictureInPictureTransitionFraction)
        } else {
            previewVideoSide = interpolate(from: 300.0, to: 240.0, value: 1.0 - self.pictureInPictureTransitionFraction)
        }
        var previewVideoSize = layout.size.aspectFitted(CGSize(width: previewVideoSide, height: previewVideoSide))
        previewVideoSize = CGSize(width: 30.0, height: 45.0).aspectFitted(previewVideoSize)
        if let minimizedVideoNode = self.minimizedVideoNode {
            var aspect = minimizedVideoNode.currentAspect
            var rotationCount = 0
            if minimizedVideoNode === self.outgoingVideoNodeValue {
                aspect = 138.0 / 240.0
            } else {
                if aspect < 1.0 {
                    aspect = 138.0 / 240.0
                } else {
                    aspect = 240.0 / 138.0
                }
                
                switch minimizedVideoNode.currentOrientation {
                case .rotation90, .rotation270:
                    rotationCount += 1
                default:
                    break
                }
                
                var mappedDeviceOrientation = self.deviceOrientation
                if case .regular = layout.metrics.widthClass, case .regular = layout.metrics.heightClass {
                    mappedDeviceOrientation = .portrait
                }
                
                switch mappedDeviceOrientation {
                case .landscapeLeft, .landscapeRight:
                    rotationCount += 1
                default:
                    break
                }
                
                if rotationCount % 2 != 0 {
                    aspect = 1.0 / aspect
                }
            }
            
            let unboundVideoSize = CGSize(width: aspect * 10000.0, height: 10000.0)
            
            previewVideoSize = unboundVideoSize.aspectFitted(CGSize(width: previewVideoSide, height: previewVideoSide))
        }
        let previewVideoY: CGFloat
        let previewVideoX: CGFloat
        
        switch self.outgoingVideoNodeCorner {
        case .topLeft:
            previewVideoX = insets.left
            previewVideoY = insets.top
        case .topRight:
            previewVideoX = layout.size.width - previewVideoSize.width - insets.right
            previewVideoY = insets.top
        case .bottomLeft:
            previewVideoX = insets.left
            previewVideoY = layout.size.height - insets.bottom - previewVideoSize.height
        case .bottomRight:
            previewVideoX = layout.size.width - previewVideoSize.width - insets.right
            previewVideoY = layout.size.height - insets.bottom - previewVideoSize.height
        }
        
        return CGRect(origin: CGPoint(x: previewVideoX, y: previewVideoY), size: previewVideoSize)
    }
    
    private func calculatePictureInPictureContainerRect(layout: ContainerViewLayout, navigationHeight: CGFloat) -> CGRect {
        let pictureInPictureTopInset: CGFloat = layout.insets(options: .statusBar).top + 44.0 + 8.0
        let pictureInPictureSideInset: CGFloat = 8.0
        let pictureInPictureSize = layout.size.fitted(CGSize(width: 240.0, height: 240.0))
        let pictureInPictureBottomInset: CGFloat = layout.insets(options: .input).bottom + 44.0 + 8.0
        
        let containerPictureInPictureFrame: CGRect
        switch self.pictureInPictureCorner {
        case .topLeft:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: pictureInPictureSideInset, y: pictureInPictureTopInset), size: pictureInPictureSize)
        case .topRight:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: layout.size.width -  pictureInPictureSideInset - pictureInPictureSize.width, y: pictureInPictureTopInset), size: pictureInPictureSize)
        case .bottomLeft:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: pictureInPictureSideInset, y: layout.size.height - pictureInPictureBottomInset - pictureInPictureSize.height), size: pictureInPictureSize)
        case .bottomRight:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: layout.size.width -  pictureInPictureSideInset - pictureInPictureSize.width, y: layout.size.height - pictureInPictureBottomInset - pictureInPictureSize.height), size: pictureInPictureSize)
        }
        return containerPictureInPictureFrame
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.validLayout = (layout, navigationBarHeight)
        
        var mappedDeviceOrientation = self.deviceOrientation
        var isCompactLayout = true
        if case .regular = layout.metrics.widthClass, case .regular = layout.metrics.heightClass {
            mappedDeviceOrientation = .portrait
            isCompactLayout = false
        }
        
        if !self.hasVideoNodes {
            self.isUIHidden = false
        }
        
        var isUIHidden = self.isUIHidden
        switch self.callState?.state {
        case .terminated, .terminating:
            isUIHidden = false
        default:
            break
        }
        
        var uiDisplayTransition: CGFloat = isUIHidden ? 0.0 : 1.0
        let pipTransitionAlpha: CGFloat = 1.0 - self.pictureInPictureTransitionFraction
        uiDisplayTransition *= pipTransitionAlpha
        
        let pinchTransitionAlpha: CGFloat = self.isVideoPinched ? 0.0 : 1.0
        
        let previousVideoButtonFrame = self.buttonsNode.videoButtonFrame().flatMap { frame -> CGRect in
            return self.buttonsNode.view.convert(frame, to: self.view)
        }
        
        let buttonsHeight: CGFloat
        if let buttonsMode = self.buttonsMode {
            buttonsHeight = self.buttonsNode.updateLayout(strings: self.presentationData.strings, mode: buttonsMode, constrainedWidth: layout.size.width, bottomInset: layout.intrinsicInsets.bottom, transition: transition)
        } else {
            buttonsHeight = 0.0
        }
        let defaultButtonsOriginY = layout.size.height - buttonsHeight
        let buttonsCollapsedOriginY = self.pictureInPictureTransitionFraction > 0.0 ? layout.size.height + 30.0 : layout.size.height + 10.0
        let buttonsOriginY = interpolate(from: buttonsCollapsedOriginY, to: defaultButtonsOriginY, value: uiDisplayTransition)
        
        let toastHeight = self.toastNode.updateLayout(strings: self.presentationData.strings, content: self.toastContent, constrainedWidth: layout.size.width, bottomInset: layout.intrinsicInsets.bottom + buttonsHeight, transition: transition)
        
        let toastSpacing: CGFloat = 22.0
        let toastCollapsedOriginY = self.pictureInPictureTransitionFraction > 0.0 ? layout.size.height : layout.size.height - max(layout.intrinsicInsets.bottom, 20.0) - toastHeight
        let toastOriginY = interpolate(from: toastCollapsedOriginY, to: defaultButtonsOriginY - toastSpacing - toastHeight, value: uiDisplayTransition)
        
        var overlayAlpha: CGFloat = min(pinchTransitionAlpha, uiDisplayTransition)
        var statusAlpha: CGFloat = overlayAlpha
        var buttonsAlpha: CGFloat = overlayAlpha
        var toastAlpha: CGFloat = min(pinchTransitionAlpha, pipTransitionAlpha)
        
        switch self.callState?.state {
        case .terminated:
            if self.ratingCallNode == nil {
                overlayAlpha *= 0.5
                toastAlpha *= 0.5
                statusAlpha = overlayAlpha
                buttonsAlpha = overlayAlpha
            } else {
                overlayAlpha = 0.0
                buttonsAlpha = 0.0
                toastAlpha *= 0.5
                statusAlpha = 1.0
            }
            
        case .terminating:
            overlayAlpha = 0.5
            toastAlpha *= 0.5
            statusAlpha = 1.0
            buttonsAlpha = 1.0
        default:
            break
        }
        
        let containerFullScreenFrame = CGRect(origin: CGPoint(), size: layout.size)
        let containerPictureInPictureFrame = self.calculatePictureInPictureContainerRect(layout: layout, navigationHeight: navigationBarHeight)
        
        let containerFrame = interpolateFrame(from: containerFullScreenFrame, to: containerPictureInPictureFrame, t: self.pictureInPictureTransitionFraction)
        
        transition.updateFrame(node: self.containerTransformationNode, frame: containerFrame)
        transition.updateSublayerTransformScale(node: self.containerTransformationNode, scale: min(1.0, containerFrame.width / layout.size.width * 1.01))
        transition.updateCornerRadius(layer: self.containerTransformationNode.layer, cornerRadius: self.pictureInPictureTransitionFraction * 10.0)
        
        transition.updateFrame(node: self.containerNode, frame: CGRect(origin: CGPoint(x: (containerFrame.width - layout.size.width) / 2.0, y: floor(containerFrame.height - layout.size.height) / 2.0), size: layout.size))
        transition.updateFrame(node: self.videoContainerNode, frame: containerFullScreenFrame)
        self.videoContainerNode.update(size: containerFullScreenFrame.size, transition: transition)
        
//        transition.updateAlpha(node: self.dimNode, alpha: pinchTransitionAlpha)
//        transition.updateFrame(node: self.dimNode, frame: containerFullScreenFrame)
    
        self.updateKeyPreviewNode(containerSize: layout.size, transition: transition)
        
        self.gradientBackgroundNode?.frame = containerFullScreenFrame
        self.gradientEffectView?.frame = self.gradientBackgroundNode?.bounds ?? .zero
        self.gradientBackgroundNode?.updateLayout(size: containerFullScreenFrame.size, transition: .immediate, extendAnimation: false, backwards: false, completion: {})
        
        
        let speakingContainerSize: CGFloat = avatarSize.width
        let speakingCenterY = containerFullScreenFrame.height * 0.34
        let speakingContainerFrame = CGRect(x: containerFullScreenFrame.midX - speakingContainerSize/2.0, y: speakingCenterY - speakingContainerSize/2.0, width: speakingContainerSize, height: speakingContainerSize)
        
//        if self.avatarNodeAnimationInProgress == false {
            transition.updateFrame(node: self.speakingContainerNode, frame: speakingContainerFrame)
            transition.updateFrame(node: self.avatarNode, frame: CGRect(origin: .zero, size: speakingContainerFrame.size))
            self.avatarNode.updateLayout(size: avatarSize)
//        }
        
        let navigationOffset: CGFloat = max(20.0, layout.safeInsets.top)
        let topOriginY = interpolate(from: -20.0, to: navigationOffset, value: uiDisplayTransition)
        
        let backSize = self.backButtonNode.measure(CGSize(width: 320.0, height: 100.0))
        if let image = self.backButtonArrowNode.image {
            transition.updateFrame(node: self.backButtonArrowNode, frame: CGRect(origin: CGPoint(x: 10.0, y: topOriginY + 24.0), size: image.size))
        }
        transition.updateFrame(node: self.backButtonNode, frame: CGRect(origin: CGPoint(x: 29.0, y: topOriginY + 24.0), size: backSize))
        
        if onEstablishedAnimationAppeared {
            transition.updateAlpha(node: self.backButtonArrowNode, alpha: overlayAlpha)
            transition.updateAlpha(node: self.backButtonNode, alpha: overlayAlpha)
        }
        
        transition.updateAlpha(node: self.toastNode, alpha: toastAlpha)
        
        let compactStatusNode = self.incomingVideoNodeValue != nil || self.outgoingVideoNodeValue != nil
        let statusOffset: CGFloat = speakingContainerFrame.maxY + 40.0
        let statusHeight = self.statusNode.updateLayout(constrainedWidth: layout.size.width, compact: compactStatusNode, transition: transition)
        let statusNodeFrame: CGRect
        if compactStatusNode {
            statusNodeFrame = CGRect(origin: CGPoint(x: 0.0, y: self.backButtonNode.frame.maxY + 20.0), size: CGSize(width: layout.size.width, height: statusHeight))
        } else {
            statusNodeFrame = CGRect(origin: CGPoint(x: 0.0, y: statusOffset), size: CGSize(width: layout.size.width, height: statusHeight))
        }
        transition.updateFrame(node: self.statusNode, frame: statusNodeFrame)
        transition.updateAlpha(node: self.statusNode, alpha: statusAlpha)
        
        if toastHeight > .leastNormalMagnitude {
            transition.updateFrame(node: self.toastNode, frame: CGRect(origin: CGPoint(x: 0.0, y: toastOriginY), size: CGSize(width: layout.size.width, height: toastHeight)))
        } else {
            transition.updateFrame(node: self.toastNode, frame: CGRect(origin: CGPoint(x: 0.0, y: toastOriginY), size: CGSize(width: layout.size.width, height: toastHeight)), delay: 0.3)
        }

        transition.updateFrame(node: self.buttonsNode, frame: CGRect(origin: CGPoint(x: 0.0, y: buttonsOriginY), size: CGSize(width: layout.size.width, height: buttonsHeight)))
        transition.updateAlpha(node: self.buttonsNode, alpha: buttonsAlpha)
        
        if let ratingCallNode = self.ratingCallNode {
            let ratingTransiton: ContainedViewLayoutTransition = ratingCallNode.frame.isEmpty ? .immediate : transition
            let horizontalInset: CGFloat = 44.0
            let buttonHeight: CGFloat = 56.0 // todo: refactor
            let availableSize: CGSize = CGSize(width: self.buttonsNode.frame.width - horizontalInset * 2, height: self.buttonsNode.frame.origin.y - statusNodeFrame.maxY + buttonHeight)
            let size = ratingCallNode.updateLayout(size: availableSize, transition: .immediate)
            
            ratingTransiton.updateFrame(node: ratingCallNode, frame: CGRect(origin: CGPoint(x: self.buttonsNode.frame.origin.x + horizontalInset, y: self.buttonsNode.frame.origin.y - size.height + buttonHeight), size: size))
        }

        let fullscreenVideoFrame = containerFullScreenFrame
        let previewVideoFrame = self.calculatePreviewVideoRect(layout: layout, navigationHeight: navigationBarHeight)
        
        if let removedMinimizedVideoNodeValue = self.removedMinimizedVideoNodeValue {
            self.removedMinimizedVideoNodeValue = nil
            
            if transition.isAnimated {
                removedMinimizedVideoNodeValue.layer.animateScale(from: 1.0, to: 0.6, duration: 0.3, removeOnCompletion: false)
                removedMinimizedVideoNodeValue.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { [weak removedMinimizedVideoNodeValue] _ in
                    removedMinimizedVideoNodeValue?.removeFromSupernode()
                })
            } else {
                removedMinimizedVideoNodeValue.removeFromSupernode()
            }
        }
        
        if let expandedVideoNode = self.expandedVideoNode {

            var expandedVideoTransition = transition
            if expandedVideoNode.frame.isEmpty || self.disableAnimationForExpandedVideoOnce {
                expandedVideoTransition = .immediate
                self.disableAnimationForExpandedVideoOnce = false
            }
            
            let animateExpandedFromAvatar = expandedVideoNode.frame.isEmpty && self.outgoingVideoNodeValue == nil
            if self.outgoingVideoNodeValue == nil {
                expandedVideoTransition = .immediate
            }
            if let removedExpandedVideoNodeValue = self.removedExpandedVideoNodeValue {
                self.removedExpandedVideoNodeValue = nil
                self.removedExpandedVideoNodeValueIsIncoming = nil
                
                expandedVideoTransition.updateFrame(node: expandedVideoNode, frame: fullscreenVideoFrame, completion: { [weak removedExpandedVideoNodeValue] _ in
                    removedExpandedVideoNodeValue?.removeFromSupernode()
                })
            } else {
                expandedVideoTransition.updateFrame(node: expandedVideoNode, frame: fullscreenVideoFrame)
            }
            
            expandedVideoNode.updateLayout(size: expandedVideoNode.frame.size, cornerRadius: 0.0, isOutgoing: expandedVideoNode === self.outgoingVideoNodeValue, deviceOrientation: mappedDeviceOrientation, isCompactLayout: isCompactLayout, transition: expandedVideoTransition)
            
            if animateExpandedFromAvatar {
                let layerTransition = Transition(transition)
                let layer = CAShapeLayer()
                layer.fillColor = UIColor.black.cgColor
                let rectFrom = CGRect(origin: self.convert(self.avatarNode.frame.origin, from: self.speakingContainerNode), size: self.avatarNode.frame.size)
                let fromPath = UIBezierPath(roundedRect: rectFrom, cornerRadius: rectFrom.height / 2.0)
                let toPath = UIBezierPath(roundedRect: fullscreenVideoFrame, cornerRadius: 44.0)
                layer.path = fromPath.cgPath
                if #available(iOS 13.0, *) {
                    layer.cornerCurve = .continuous
                }
                expandedVideoNode.layer.mask = layer
                layerTransition.setShapeLayerPath(layer: layer, path: toPath.cgPath, completion: { [weak expandedVideoNode, weak layer] _ in
                    guard let layer = layer else { return }
                    layerTransition.setCornerRadius(layer: layer, cornerRadius: 0.0, completion: { [weak expandedVideoNode] _ in
                        expandedVideoNode?.layer.mask = nil
                    })
                })

                let expandedVideoShortTransition = ContainedViewLayoutTransition(transition, durationFactor: 1.0 / 3.0)
                expandedVideoNode.alpha = 0.0
                expandedVideoShortTransition.updateAlpha(node: expandedVideoNode, alpha: 1.0)
            } else {
                transition.updateAlpha(node: expandedVideoNode, alpha: 1.0)
            }
            
            self.animateRequestedVideoOnce = false
            if self.animateRequestedVideoOnce {
                self.animateRequestedVideoOnce = false
                if expandedVideoNode === self.outgoingVideoNodeValue {
                    let videoButtonFrame = self.buttonsNode.videoButtonFrame().flatMap { frame -> CGRect in
                        return self.buttonsNode.view.convert(frame, to: self.view)
                    }
                    
                    if let previousVideoButtonFrame = previousVideoButtonFrame, let videoButtonFrame = videoButtonFrame {
                        expandedVideoNode.animateRadialMask(from: previousVideoButtonFrame, to: videoButtonFrame)
                    }
                }
            }
        } else {
            if let removedExpandedVideoNodeValue = self.removedExpandedVideoNodeValue {
                self.removedExpandedVideoNodeValue = nil
                let removedExpandedVideoNodeValueIsIncoming = self.removedExpandedVideoNodeValueIsIncoming
                self.removedExpandedVideoNodeValueIsIncoming = nil
                if transition.isAnimated, removedExpandedVideoNodeValueIsIncoming == true {
                    let layerTransition = Transition(transition)
                    let shortLayerTransition: Transition = .init(animation: .curve(duration: 0.05, curve: .spring))
                    
                    let layer = CAShapeLayer()
                    layer.fillColor = UIColor.black.cgColor
                    let fromPath = UIBezierPath(roundedRect: fullscreenVideoFrame, cornerRadius: 1.0)
                    let rectTo = CGRect(origin: self.convert(self.avatarNode.frame.origin, from: self.speakingContainerNode), size: self.avatarNode.frame.size)
                    
                    shortLayerTransition.setCornerRadius(layer: layer, cornerRadius: 44.0)
                    let toPath = UIBezierPath(roundedRect: rectTo, cornerRadius: rectTo.height / 2.0)
                    layer.path = fromPath.cgPath
                    removedExpandedVideoNodeValue.layer.mask = layer
                    
                    layerTransition.setShapeLayerPath(layer: layer, path: toPath.cgPath)
                    let prevColor = self.videoContainerNode.backgroundColor
                    let videoContainerColor = UIColor.clear
                    self.videoContainerNode.backgroundColor = videoContainerColor
                    removedExpandedVideoNodeValue.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.1, delay: 0.2, removeOnCompletion: false, completion: { [weak self, weak removedExpandedVideoNodeValue] _ in
                        removedExpandedVideoNodeValue?.removeFromSupernode()
                        if self?.videoContainerNode.backgroundColor === videoContainerColor {
                            self?.videoContainerNode.backgroundColor = prevColor
                        }
                    })
                } else if transition.isAnimated {
                    transition.updateCornerRadius(layer: removedExpandedVideoNodeValue.layer, cornerRadius: 60.0)
                    var toPosition = removedExpandedVideoNodeValue.layer.position
                    toPosition.y += removedExpandedVideoNodeValue.frame.height
                    removedExpandedVideoNodeValue.layer.animatePosition(from: removedExpandedVideoNodeValue.layer.position, to: toPosition, duration: 0.3, removeOnCompletion: false)
                    removedExpandedVideoNodeValue.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { [weak removedExpandedVideoNodeValue] _ in
                        removedExpandedVideoNodeValue?.removeFromSupernode()
                    })
                } else {
                    removedExpandedVideoNodeValue.removeFromSupernode()
                }
            }
        }
        
        
        if let minimizedVideoNode = self.minimizedVideoNode {
            transition.updateAlpha(node: minimizedVideoNode, alpha: min(pipTransitionAlpha, pinchTransitionAlpha))
            var minimizedVideoTransition = transition
            if self.minimizedVideoDraggingPosition == nil {
                
                if let animationForExpandedVideoSnapshotView = self.animationForExpandedVideoSnapshotView {
                    self.containerNode.view.insertSubview(animationForExpandedVideoSnapshotView, aboveSubview: self.videoContainerNode.view)

                    transition.updateAlpha(layer: animationForExpandedVideoSnapshotView.layer, alpha: 0.0, completion: { [weak animationForExpandedVideoSnapshotView] _ in
                        animationForExpandedVideoSnapshotView?.removeFromSuperview()
                    })
                    self.animationForExpandedVideoSnapshotView = nil
                    minimizedVideoTransition = .immediate
                }
                
                if let animationForMinimizedVideoSnapshotView = self.animationForMinimizedVideoSnapshotView {
                    self.containerNode.view.insertSubview(animationForMinimizedVideoSnapshotView, aboveSubview: self.videoContainerNode.view)
                    
                    transition.updateAlpha(layer: animationForMinimizedVideoSnapshotView.layer, alpha: 0.0, completion: { [weak animationForMinimizedVideoSnapshotView] _ in
                        animationForMinimizedVideoSnapshotView?.removeFromSuperview()
                    })
                    self.animationForMinimizedVideoSnapshotView = nil
                    minimizedVideoTransition = .immediate
                }

                if minimizedVideoNode.frame.isEmpty {
                    minimizedVideoNode.updateLayout(size: fullscreenVideoFrame.size, cornerRadius: interpolate(from: 14.0, to: 24.0, value: self.pictureInPictureTransitionFraction), isOutgoing: minimizedVideoNode === self.outgoingVideoNodeValue, deviceOrientation: mappedDeviceOrientation, isCompactLayout: layout.metrics.widthClass == .compact, transition: .immediate)
                    minimizedVideoNode.frame = fullscreenVideoFrame
                }
                minimizedVideoTransition.updateFrame(node: minimizedVideoNode, frame: previewVideoFrame)
                minimizedVideoNode.updateLayout(size: previewVideoFrame.size, cornerRadius: interpolate(from: 14.0, to: 24.0, value: self.pictureInPictureTransitionFraction), isOutgoing: minimizedVideoNode === self.outgoingVideoNodeValue, deviceOrientation: mappedDeviceOrientation, isCompactLayout: layout.metrics.widthClass == .compact, transition: minimizedVideoTransition)
            }
            
            self.animationForExpandedVideoSnapshotView = nil
        }
        
        let keyTextSize = self.keyButtonNode.frame.size
        transition.updateFrame(node: self.keyButtonNode, frame: CGRect(origin: CGPoint(x: layout.size.width - keyTextSize.width - 8.0, y: topOriginY + 21.0), size: keyTextSize))
        transition.updateAlpha(node: self.keyButtonNode, alpha: overlayAlpha)
        
        if let debugNode = self.debugNode {
            transition.updateFrame(node: debugNode, frame: CGRect(origin: CGPoint(), size: layout.size))
        }
        
        let requestedAspect: CGFloat
        if case .compact = layout.metrics.widthClass, case .compact = layout.metrics.heightClass {
            var isIncomingVideoRotated = false
            var rotationCount = 0
            
            switch mappedDeviceOrientation {
            case .portrait:
                break
            case .landscapeLeft:
                rotationCount += 1
            case .landscapeRight:
                rotationCount += 1
            case .portraitUpsideDown:
                 break
            default:
                break
            }
            
            if rotationCount % 2 != 0 {
                isIncomingVideoRotated = true
            }
            
            if !isIncomingVideoRotated {
                requestedAspect = layout.size.width / layout.size.height
            } else {
                requestedAspect = 0.0
            }
        } else {
            requestedAspect = 0.0
        }
        if self.currentRequestedAspect != requestedAspect {
            self.currentRequestedAspect = requestedAspect
            if !self.sharedContext.immediateExperimentalUISettings.disableVideoAspectScaling {
                self.call.setRequestedVideoAspect(Float(requestedAspect))
            }
        }
    }

    private func updateKeyPreviewNode(containerSize: CGSize, transition: ContainedViewLayoutTransition) {
        guard let keyPreviewNode = self.keyPreviewNode else { return }
        let size = keyPreviewNode.updateLayout(size: containerSize, transition: .immediate)
        let origin = CGPoint(x: floor((containerSize.width - size.width) / 2.0), y: self.backButtonNode.frame.maxY + 40.0)
        transition.updateFrame(node: keyPreviewNode, frame: CGRect(origin: origin, size: size))
    }

    @objc func keyPressed() {
        if self.keyPreviewNode == nil, let keyText = self.keyTextData?.1, let peer = self.peer {
            // TODO: move strings to localization
            let titleText = "This call is end-to end encrypted"
            let buttonText = "OK"
            let keyPreviewNode = ContestCallControllerKeyPreviewNode(context: self.accountContext, keyText: keyText, titleText: titleText, infoText: self.presentationData.strings.Call_EmojiDescription(EnginePeer(peer).compactDisplayTitle).string.replacingOccurrences(of: "%%", with: "%"), buttonText: buttonText, light: self.incomingVideoNodeValue == nil && self.outgoingVideoNodeValue == nil, dismiss: { [weak self] in
                if let _ = self?.keyPreviewNode {
                    self?.backPressed()
                }
            })

            self.containerNode.insertSubnode(keyPreviewNode, aboveSubnode: self.statusNode)
            self.keyPreviewNode = keyPreviewNode
            
            if let (validLayout, _) = self.validLayout {
                self.updateKeyPreviewNode(containerSize: validLayout.size, transition: .immediate)
                self.keyButtonNode.isHidden = true
                keyPreviewNode.animateIn(from: self.keyButtonNode.frame, fromNode: self.keyButtonNode, parentNode: self)
                
                self.speakingContainerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
                self.speakingContainerNode.layer.animateScale(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            }
            
            self.updateDimVisibility()
        }
    }
    
    @objc func backPressed() {
        if let keyPreviewNode = self.keyPreviewNode {
            self.keyPreviewNode = nil
            keyPreviewNode.animateOut(to: self.keyButtonNode.frame, toNode: self.keyButtonNode, parentNode: self, completion: { [weak self, weak keyPreviewNode] in
                self?.keyButtonNode.isHidden = false
                keyPreviewNode?.removeFromSupernode()
            })
            self.speakingContainerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2, removeOnCompletion: false)
            self.speakingContainerNode.layer.animateScale(from: 0.0, to: 1.0, duration: 0.2, removeOnCompletion: false)
            self.updateDimVisibility()
        } else if self.hasVideoNodes {
            if let (layout, navigationHeight) = self.validLayout {
                self.pictureInPictureTransitionFraction = 1.0
                self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
            }
        } else {
            self.back?()
        }
    }
    
    private var hasVideoNodes: Bool {
        return self.expandedVideoNode != nil || self.minimizedVideoNode != nil
    }
    
    private var debugTapCounter: (Double, Int) = (0.0, 0)
    
    private func areUserActionsDisabledNow() -> Bool {
        return CACurrentMediaTime() < self.disableActionsUntilTimestamp
    }
    
    @objc func tapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            if !self.pictureInPictureTransitionFraction.isZero {
                self.view.window?.endEditing(true)
                
                if let (layout, navigationHeight) = self.validLayout {
                    self.pictureInPictureTransitionFraction = 0.0
                    
                    self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
                }
            } else if let _ = self.keyPreviewNode {
                self.backPressed()
            } else {
                if self.hasVideoNodes {
                    let point = recognizer.location(in: recognizer.view)
                    if let expandedVideoNode = self.expandedVideoNode, let minimizedVideoNode = self.minimizedVideoNode, minimizedVideoNode.frame.contains(point) {
                        if !self.areUserActionsDisabledNow() {
                            let minimizedCopyView = minimizedVideoNode.view.snapshotView(afterScreenUpdates: false)
                            minimizedCopyView?.frame = minimizedVideoNode.frame
                            let expandedCopyView = expandedVideoNode.view.snapshotView(afterScreenUpdates: false)
                            expandedCopyView?.frame = expandedVideoNode.frame

                            self.expandedVideoNode = minimizedVideoNode
                            self.minimizedVideoNode = expandedVideoNode
                            if let supernode = expandedVideoNode.supernode {
                                supernode.insertSubnode(expandedVideoNode, aboveSubnode: minimizedVideoNode)
                            }
                            self.disableActionsUntilTimestamp = CACurrentMediaTime() + 0.3
                            if let (layout, navigationBarHeight) = self.validLayout {
                                self.disableAnimationForExpandedVideoOnce = true
                                self.animationForExpandedVideoSnapshotView = minimizedCopyView
                                self.animationForMinimizedVideoSnapshotView = expandedCopyView
                                self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                            }
                        }
                    } else {
                        var updated = false
                        if let callState = self.callState {
                            switch callState.state {
                            case .active, .connecting, .reconnecting:
                                self.isUIHidden = !self.isUIHidden
                                updated = true
                            default:
                                break
                            }
                        }
                        if updated, let (layout, navigationBarHeight) = self.validLayout {
                            self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                        }
                    }
                } else {
                    let point = recognizer.location(in: recognizer.view)
                    if self.statusNode.frame.contains(point) {
                        if self.easyDebugAccess {
                            self.presentDebugNode()
                        } else {
                            let timestamp = CACurrentMediaTime()
                            if self.debugTapCounter.0 < timestamp - 0.75 {
                                self.debugTapCounter.0 = timestamp
                                self.debugTapCounter.1 = 0
                            }
                            
                            if self.debugTapCounter.0 >= timestamp - 0.75 {
                                self.debugTapCounter.0 = timestamp
                                self.debugTapCounter.1 += 1
                            }
                            
                            if self.debugTapCounter.1 >= 10 {
                                self.debugTapCounter.1 = 0
                                
                                self.presentDebugNode()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func presentDebugNode() {
        guard self.debugNode == nil else {
            return
        }
        
        self.forceReportRating = true
        
        let debugNode = CallDebugNode(signal: self.debugInfo)
        debugNode.dismiss = { [weak self] in
            if let strongSelf = self {
                strongSelf.debugNode?.removeFromSupernode()
                strongSelf.debugNode = nil
            }
        }
        self.addSubnode(debugNode)
        self.debugNode = debugNode
        
        if let (layout, navigationBarHeight) = self.validLayout {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
        }
    }
    
    private var minimizedVideoInitialPosition: CGPoint?
    private var minimizedVideoDraggingPosition: CGPoint?
    
    private func nodeLocationForPosition(layout: ContainerViewLayout, position: CGPoint, velocity: CGPoint) -> VideoNodeCorner {
        let layoutInsets = UIEdgeInsets()
        var result = CGPoint()
        if position.x < layout.size.width / 2.0 {
            result.x = 0.0
        } else {
            result.x = 1.0
        }
        if position.y < layoutInsets.top + (layout.size.height - layoutInsets.bottom - layoutInsets.top) / 2.0 {
            result.y = 0.0
        } else {
            result.y = 1.0
        }
        
        let currentPosition = result
        
        let angleEpsilon: CGFloat = 30.0
        var shouldHide = false
        
        if (velocity.x * velocity.x + velocity.y * velocity.y) >= 500.0 * 500.0 {
            let x = velocity.x
            let y = velocity.y
            
            var angle = atan2(y, x) * 180.0 / CGFloat.pi * -1.0
            if angle < 0.0 {
                angle += 360.0
            }
            
            if currentPosition.x.isZero && currentPosition.y.isZero {
                if ((angle > 0 && angle < 90 - angleEpsilon) || angle > 360 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 0.0
                } else if (angle > 180 + angleEpsilon && angle < 270 + angleEpsilon) {
                    result.x = 0.0
                    result.y = 1.0
                } else if (angle > 270 + angleEpsilon && angle < 360 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 1.0
                } else {
                    shouldHide = true
                }
            } else if !currentPosition.x.isZero && currentPosition.y.isZero {
                if (angle > 90 + angleEpsilon && angle < 180 + angleEpsilon) {
                    result.x = 0.0
                    result.y = 0.0
                }
                else if (angle > 270 - angleEpsilon && angle < 360 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 1.0
                }
                else if (angle > 180 + angleEpsilon && angle < 270 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 1.0
                }
                else {
                    shouldHide = true
                }
            } else if currentPosition.x.isZero && !currentPosition.y.isZero {
                if (angle > 90 - angleEpsilon && angle < 180 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 0.0
                }
                else if (angle < angleEpsilon || angle > 270 + angleEpsilon) {
                    result.x = 1.0
                    result.y = 1.0
                }
                else if (angle > angleEpsilon && angle < 90 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 0.0
                }
                else if (!shouldHide) {
                    shouldHide = true
                }
            } else if !currentPosition.x.isZero && !currentPosition.y.isZero {
                if (angle > angleEpsilon && angle < 90 + angleEpsilon) {
                    result.x = 1.0
                    result.y = 0.0
                }
                else if (angle > 180 - angleEpsilon && angle < 270 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 1.0
                }
                else if (angle > 90 + angleEpsilon && angle < 180 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 0.0
                }
                else if (!shouldHide) {
                    shouldHide = true
                }
            }
        }
        
        if result.x.isZero {
            if result.y.isZero {
                return .topLeft
            } else {
                return .bottomLeft
            }
        } else {
            if result.y.isZero {
                return .topRight
            } else {
                return .bottomRight
            }
        }
    }
    
    @objc private func panGesture(_ recognizer: CallPanGestureRecognizer) {
        guard self.ratingCallNode == nil else {
            return
        }
        switch recognizer.state {
            case .began:
                guard let location = recognizer.firstLocation else {
                    return
                }
                if self.pictureInPictureTransitionFraction.isZero, let expandedVideoNode = self.expandedVideoNode, let minimizedVideoNode = self.minimizedVideoNode, minimizedVideoNode.frame.contains(location), expandedVideoNode.frame != minimizedVideoNode.frame {
                    self.minimizedVideoInitialPosition = minimizedVideoNode.position
                } else if self.hasVideoNodes {
                    self.minimizedVideoInitialPosition = nil
                    if !self.pictureInPictureTransitionFraction.isZero {
                        self.pictureInPictureGestureState = .dragging(initialPosition: self.containerTransformationNode.position, draggingPosition: self.containerTransformationNode.position)
                    } else {
                        self.pictureInPictureGestureState = .collapsing(didSelectCorner: false)
                    }
                } else {
                    self.pictureInPictureGestureState = .none
                }
                self.dismissAllTooltips?()
            case .changed:
                if let minimizedVideoNode = self.minimizedVideoNode, let minimizedVideoInitialPosition = self.minimizedVideoInitialPosition {
                    let translation = recognizer.translation(in: self.view)
                    let minimizedVideoDraggingPosition = CGPoint(x: minimizedVideoInitialPosition.x + translation.x, y: minimizedVideoInitialPosition.y + translation.y)
                    self.minimizedVideoDraggingPosition = minimizedVideoDraggingPosition
                    minimizedVideoNode.position = minimizedVideoDraggingPosition
                } else {
                    switch self.pictureInPictureGestureState {
                    case .none:
                        let offset = recognizer.translation(in: self.view).y
                        var bounds = self.bounds
                        bounds.origin.y = -offset
                        self.bounds = bounds
                    case let .collapsing(didSelectCorner):
                        if let (layout, navigationHeight) = self.validLayout {
                            let offset = recognizer.translation(in: self.view)
                            if !didSelectCorner {
                                self.pictureInPictureGestureState = .collapsing(didSelectCorner: true)
                                if offset.x < 0.0 {
                                    self.pictureInPictureCorner = .topLeft
                                } else {
                                    self.pictureInPictureCorner = .topRight
                                }
                            }
                            let maxOffset: CGFloat = min(300.0, layout.size.height / 2.0)
                            
                            let offsetTransition = max(0.0, min(1.0, abs(offset.y) / maxOffset))
                            self.pictureInPictureTransitionFraction = offsetTransition
                            switch self.pictureInPictureCorner {
                            case .topRight, .bottomRight:
                                self.pictureInPictureCorner = offset.y < 0.0 ? .topRight : .bottomRight
                            case .topLeft, .bottomLeft:
                                self.pictureInPictureCorner = offset.y < 0.0 ? .topLeft : .bottomLeft
                            }
                            
                            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .immediate)
                        }
                    case .dragging(let initialPosition, var draggingPosition):
                        let translation = recognizer.translation(in: self.view)
                        draggingPosition.x = initialPosition.x + translation.x
                        draggingPosition.y = initialPosition.y + translation.y
                        self.pictureInPictureGestureState = .dragging(initialPosition: initialPosition, draggingPosition: draggingPosition)
                        self.containerTransformationNode.position = draggingPosition
                    }
                }
            case .cancelled, .ended:
                if let minimizedVideoNode = self.minimizedVideoNode, let _ = self.minimizedVideoInitialPosition, let minimizedVideoDraggingPosition = self.minimizedVideoDraggingPosition {
                    self.minimizedVideoInitialPosition = nil
                    self.minimizedVideoDraggingPosition = nil
                    
                    if let (layout, navigationHeight) = self.validLayout {
                        self.outgoingVideoNodeCorner = self.nodeLocationForPosition(layout: layout, position: minimizedVideoDraggingPosition, velocity: recognizer.velocity(in: self.view))
                        
                        let videoFrame = self.calculatePreviewVideoRect(layout: layout, navigationHeight: navigationHeight)
                        minimizedVideoNode.frame = videoFrame
                        minimizedVideoNode.layer.animateSpring(from: NSValue(cgPoint: CGPoint(x: minimizedVideoDraggingPosition.x - videoFrame.midX, y: minimizedVideoDraggingPosition.y - videoFrame.midY)), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: 0.5, delay: 0.0, initialVelocity: 0.0, damping: 110.0, removeOnCompletion: true, additive: true, completion: nil)
                    }
                } else {
                    switch self.pictureInPictureGestureState {
                    case .none:
                        let velocity = recognizer.velocity(in: self.view).y
                        if abs(velocity) < 100.0 {
                            var bounds = self.bounds
                            let previous = bounds
                            bounds.origin = CGPoint()
                            self.bounds = bounds
                            self.layer.animateBounds(from: previous, to: bounds, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring)
                        } else {
                            var bounds = self.bounds
                            let previous = bounds
                            bounds.origin = CGPoint(x: 0.0, y: velocity > 0.0 ? -bounds.height: bounds.height)
                            self.bounds = bounds
                            self.layer.animateBounds(from: previous, to: bounds, duration: 0.15, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, completion: { [weak self] _ in
                                self?.dismissedInteractively?()
                            })
                        }
                    case .collapsing:
                        self.pictureInPictureGestureState = .none
                        let velocity = recognizer.velocity(in: self.view).y
                        if abs(velocity) < 100.0 && self.pictureInPictureTransitionFraction < 0.5 {
                            if let (layout, navigationHeight) = self.validLayout {
                                self.pictureInPictureTransitionFraction = 0.0
                                
                                self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
                            }
                        } else {
                            if let (layout, navigationHeight) = self.validLayout {
                                self.pictureInPictureTransitionFraction = 1.0
                                
                                self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
                            }
                        }
                    case let .dragging(initialPosition, _):
                        self.pictureInPictureGestureState = .none
                        if let (layout, navigationHeight) = self.validLayout {
                            let translation = recognizer.translation(in: self.view)
                            let draggingPosition = CGPoint(x: initialPosition.x + translation.x, y: initialPosition.y + translation.y)
                            self.pictureInPictureCorner = self.nodeLocationForPosition(layout: layout, position: draggingPosition, velocity: recognizer.velocity(in: self.view))
                            
                            let containerFrame = self.calculatePictureInPictureContainerRect(layout: layout, navigationHeight: navigationHeight)
                            self.containerTransformationNode.frame = containerFrame
                            containerTransformationNode.layer.animateSpring(from: NSValue(cgPoint: CGPoint(x: draggingPosition.x - containerFrame.midX, y: draggingPosition.y - containerFrame.midY)), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: 0.5, delay: 0.0, initialVelocity: 0.0, damping: 110.0, removeOnCompletion: true, additive: true, completion: nil)
                        }
                    }
                }
            default:
                break
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        self.startInteractiveUI()
        if self.debugNode != nil {
            return super.hitTest(point, with: event)
        }
        if let ratingCallNode = self.ratingCallNode {
            if ratingCallNode.frame.contains(point) == true {
                return super.hitTest(point, with: event)
            } else {
                return nil
            }
        }
        if self.containerTransformationNode.frame.contains(point) {
            return self.containerTransformationNode.view.hitTest(self.view.convert(point, to: self.containerTransformationNode.view), with: event)
        }
        return nil
    }
}
