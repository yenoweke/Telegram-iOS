import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import MediaPlayer
import TelegramPresentationData

final class ContestCallControllerButtonsNode: ASDisplayNode, CallControllerButtonsNodeProtocol {
    private var buttonNodes: [ButtonDescription.Key: ContestCallButtonNode] = [:]
    
    private var mode: CallControllerButtonsMode?
    
    private var validLayout: (CGFloat, CGFloat)?
    
    var isMuted = false
    
    var acceptOrEnd: (() -> Void)?
    var decline: (() -> Void)?
    var mute: (() -> Void)?
    var speaker: (() -> Void)?
    var toggleVideo: (() -> Void)?
    var rotateCamera: (() -> Void)?
    
    init(strings: PresentationStrings) {
        super.init()
    }
    
    func updateLayout(strings: PresentationStrings, mode: CallControllerButtonsMode, constrainedWidth: CGFloat, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGFloat {
        self.validLayout = (constrainedWidth, bottomInset)
        
        self.mode = mode
        
        if let mode = self.mode {
            return self.updateButtonsLayout(strings: strings, mode: mode, width: constrainedWidth, bottomInset: bottomInset, animated: transition.isAnimated)
        } else {
            return 0.0
        }
    }
    
    private var appliedMode: CallControllerButtonsMode?
    
    func videoButtonFrame() -> CGRect? {
        return self.buttonNodes[.enableCamera]?.frame
    }
    
    private func updateButtonsLayout(strings: PresentationStrings, mode: CallControllerButtonsMode, width: CGFloat, bottomInset: CGFloat, animated: Bool) -> CGFloat {
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.3, curve: .spring)
        } else {
            transition = .immediate
        }
        
        let previousMode = self.appliedMode
        self.appliedMode = mode
        
        var animatePositionsWithDelay = false
        if let previousMode = previousMode {
            switch previousMode {
            case .incoming, .outgoingRinging:
                if case .active = mode {
                    animatePositionsWithDelay = true
                }
            default:
                break
            }
        }
        
        let minSmallButtonSideInset: CGFloat = width > 320.0 ? 30.0 : 16.0
        let maxSmallButtonSpacing: CGFloat = 36.0
        let buttonSize: CGFloat = 56.0
        
        struct PlacedButton {
            let button: ButtonDescription
            let frame: CGRect
        }
        
        let speakerMode: CallControllerButtonsSpeakerMode
        var videoState: CallControllerButtonsMode.VideoState
        let hasAudioRouteMenu: Bool
        switch mode {
        case .incoming(let speakerModeValue, let hasAudioRouteMenuValue, let videoStateValue), .outgoingRinging(let speakerModeValue, let hasAudioRouteMenuValue, let videoStateValue), .active(let speakerModeValue, let hasAudioRouteMenuValue, let videoStateValue):
            speakerMode = speakerModeValue
            videoState = videoStateValue
            hasAudioRouteMenu = hasAudioRouteMenuValue
        }
        
        enum MappedState {
            case incomingRinging
            case outgoingRinging
            case active
        }
        
        let mappedState: MappedState
        switch mode {
        case .incoming:
            mappedState = .incomingRinging
        case .outgoingRinging:
            mappedState = .outgoingRinging
        case let .active(_, _, videoStateValue):
            mappedState = .active
            videoState = videoStateValue
        }
        
        var buttons: [PlacedButton] = []
        switch mappedState {
        case .incomingRinging, .outgoingRinging:
            var topButtons: [ButtonDescription] = []
            
            let soundOutput: ButtonDescription.SoundOutput
            switch speakerMode {
                case .none, .builtin:
                    soundOutput = .builtin
                case .speaker:
                    soundOutput = .speaker
                case .headphones:
                    soundOutput = .headphones
                case let .bluetooth(type):
                    switch type {
                        case .generic:
                            soundOutput = .bluetooth
                        case .airpods:
                            soundOutput = .airpods
                        case .airpodsPro:
                            soundOutput = .airpodsPro
                        case .airpodsMax:
                            soundOutput = .airpodsMax
                }
            }
            
            if videoState.isAvailable {
                let isCameraActive: Bool
                let isScreencastActive: Bool
                let isCameraInitializing: Bool
                if videoState.hasVideo {
                    isCameraActive = videoState.isCameraActive
                    isScreencastActive = videoState.isScreencastActive
                    isCameraInitializing = videoState.isInitializingCamera
                } else {
                    isCameraActive = false
                    isScreencastActive = false
                    isCameraInitializing = videoState.isInitializingCamera
                }
                
                if videoState.hasVideo {
                    if !isScreencastActive {
                        topButtons.append(.switchCamera(isCameraActive && !isCameraInitializing))
                    }
                    topButtons.append(.enableCamera(isActive: isCameraActive || isScreencastActive, isEnabled: false, isLoading: isCameraInitializing, isScreencast: isScreencastActive))
                    if hasAudioRouteMenu {
                        topButtons.append(.soundOutput(soundOutput))
                    } else {
                        topButtons.append(.mute(self.isMuted))
                    }
                } else {
                    topButtons.append(.soundOutput(soundOutput))
                    topButtons.append(.enableCamera(isActive: isCameraActive || isScreencastActive, isEnabled: false, isLoading: isCameraInitializing, isScreencast: isScreencastActive))
                    topButtons.append(.mute(self.isMuted))
                }
            } else {
                topButtons.append(.soundOutput(soundOutput))
                topButtons.append(.mute(self.isMuted))
            }
            
            if case .incomingRinging = mappedState {
                topButtons.append(.end(.cancel))
                topButtons.append(.accept)
            } else {
                topButtons.append(.end(.cancel))
            }
            
            let topButtonsContentWidth = CGFloat(topButtons.count) * buttonSize
            let topButtonsAvailableSpacingWidth = width - topButtonsContentWidth - minSmallButtonSideInset * 2.0
            let topButtonsSpacing = min(maxSmallButtonSpacing, topButtonsAvailableSpacingWidth / CGFloat(topButtons.count - 1))
            let topButtonsWidth = CGFloat(topButtons.count) * buttonSize + CGFloat(topButtons.count - 1) * topButtonsSpacing
            var topButtonsLeftOffset = floor((width - topButtonsWidth) / 2.0)
            for button in topButtons {
                buttons.append(PlacedButton(button: button, frame: CGRect(origin: CGPoint(x: topButtonsLeftOffset, y: 0.0), size: CGSize(width: buttonSize, height: buttonSize))))
                topButtonsLeftOffset += buttonSize + topButtonsSpacing
            }
            
        case .active:
            if videoState.hasVideo {
                let isCameraActive: Bool
                let isScreencastActive: Bool
                let isCameraEnabled: Bool
                let isCameraInitializing: Bool
                if videoState.hasVideo {
                    isCameraActive = videoState.isCameraActive
                    isScreencastActive = videoState.isScreencastActive
                    isCameraEnabled = videoState.canChangeStatus
                    isCameraInitializing = videoState.isInitializingCamera
                } else {
                    isCameraActive = false
                    isScreencastActive = false
                    isCameraEnabled = videoState.canChangeStatus
                    isCameraInitializing = videoState.isInitializingCamera
                }
                
                var topButtons: [ButtonDescription] = []
                
                let soundOutput: ButtonDescription.SoundOutput
                switch speakerMode {
                    case .none, .builtin:
                        soundOutput = .builtin
                    case .speaker:
                        soundOutput = .speaker
                    case .headphones:
                        soundOutput = .headphones
                    case let .bluetooth(type):
                        switch type {
                            case .generic:
                                soundOutput = .bluetooth
                            case .airpods:
                                soundOutput = .airpods
                            case .airpodsPro:
                                soundOutput = .airpodsPro
                            case .airpodsMax:
                                soundOutput = .airpodsMax
                    }
                }

                
                if !isScreencastActive {
                    if isCameraActive {
                        topButtons.append(.switchCamera(isCameraActive && !isCameraInitializing))
                    } else {
                        topButtons.append(.soundOutput(soundOutput))
                    }
                }
                
                topButtons.append(.enableCamera(isActive: isCameraActive || isScreencastActive, isEnabled: isCameraEnabled, isLoading: isCameraInitializing, isScreencast: isScreencastActive))
                
                if hasAudioRouteMenu && isCameraEnabled {
                    topButtons.append(.soundOutput(soundOutput))
                } else {
                    topButtons.append(.mute(isMuted))
                }
                
                topButtons.append(.end(.cancel))
                
                let topButtonsContentWidth = CGFloat(topButtons.count) * buttonSize
                let topButtonsAvailableSpacingWidth = width - topButtonsContentWidth - minSmallButtonSideInset * 2.0
                let topButtonsSpacing = min(maxSmallButtonSpacing, topButtonsAvailableSpacingWidth / CGFloat(topButtons.count - 1))
                let topButtonsWidth = CGFloat(topButtons.count) * buttonSize + CGFloat(topButtons.count - 1) * topButtonsSpacing
                var topButtonsLeftOffset = floor((width - topButtonsWidth) / 2.0)
                for button in topButtons {
                    buttons.append(PlacedButton(button: button, frame: CGRect(origin: CGPoint(x: topButtonsLeftOffset, y: 0.0), size: CGSize(width: buttonSize, height: buttonSize))))
                    topButtonsLeftOffset += buttonSize + topButtonsSpacing
                }
            } else {
                var topButtons: [ButtonDescription] = []

                let isCameraActive: Bool
                let isScreencastActive: Bool
                let isCameraEnabled: Bool
                let isCameraInitializing: Bool
                if videoState.hasVideo {
                    isCameraActive = videoState.isCameraActive
                    isScreencastActive = videoState.isScreencastActive
                    isCameraEnabled = videoState.canChangeStatus
                    isCameraInitializing = videoState.isInitializingCamera
                } else {
                    isCameraActive = false
                    isScreencastActive = false
                    isCameraEnabled = videoState.canChangeStatus
                    isCameraInitializing = videoState.isInitializingCamera
                }
                
                let soundOutput: ButtonDescription.SoundOutput
                switch speakerMode {
                    case .none, .builtin:
                        soundOutput = .builtin
                    case .speaker:
                        soundOutput = .speaker
                    case .headphones:
                        soundOutput = .bluetooth
                    case let .bluetooth(type):
                        switch type {
                            case .generic:
                                soundOutput = .bluetooth
                            case .airpods:
                                soundOutput = .airpods
                            case .airpodsPro:
                                soundOutput = .airpodsPro
                            case .airpodsMax:
                                soundOutput = .airpodsMax
                    }
                }
                
                topButtons.append(.soundOutput(soundOutput))
                topButtons.append(.enableCamera(isActive: isCameraActive || isScreencastActive, isEnabled: isCameraEnabled, isLoading: isCameraInitializing, isScreencast: isScreencastActive))
                topButtons.append(.mute(self.isMuted))
                topButtons.append(.end(.cancel))
                
                let topButtonsContentWidth = CGFloat(topButtons.count) * buttonSize
                let topButtonsAvailableSpacingWidth = width - topButtonsContentWidth - minSmallButtonSideInset * 2.0
                let topButtonsSpacing = min(maxSmallButtonSpacing, topButtonsAvailableSpacingWidth / CGFloat(topButtons.count - 1))
                let topButtonsWidth = CGFloat(topButtons.count) * buttonSize + CGFloat(topButtons.count - 1) * topButtonsSpacing
                var topButtonsLeftOffset = floor((width - topButtonsWidth) / 2.0)
                for button in topButtons {
                    buttons.append(PlacedButton(button: button, frame: CGRect(origin: CGPoint(x: topButtonsLeftOffset, y: 0.0), size: CGSize(width: buttonSize, height: buttonSize))))
                    topButtonsLeftOffset += buttonSize + topButtonsSpacing
                }
            }
        }
        let height = buttonSize + max(bottomInset + 52.0, 46.0)
        
        let delayIncrement = 0.015
        var validKeys: [ButtonDescription.Key] = []
        for button in buttons {
            validKeys.append(button.button.key)
            var buttonTransition = transition
            var animateButtonIn = false
            let buttonNode: ContestCallButtonNode
            if let current = self.buttonNodes[button.button.key] {
                buttonNode = current
            } else {
                buttonNode = ContestCallButtonNode()
                self.buttonNodes[button.button.key] = buttonNode
                self.addSubnode(buttonNode)
                buttonNode.addTarget(self, action: #selector(self.buttonPressed(_:)), forControlEvents: .touchUpInside)
                buttonTransition = .immediate
                animateButtonIn = transition.isAnimated
            }
            
            let (buttonContent, buttonText, buttonAccessibilityLabel, buttonAccessibilityValue, buttonAccessibilityTraits) = makeButtonContent(button.button, strings, forContest: true)
            
            var buttonDelay = 0.0
            if animatePositionsWithDelay {
                switch button.button.key {
                case .enableCamera:
                    buttonDelay = 0.0
                case .mute:
                    buttonDelay = delayIncrement * 1.0
                case .switchCamera:
                    buttonDelay = delayIncrement * 2.0
                case .acceptOrEnd:
                    buttonDelay = delayIncrement * 3.0
                default:
                    break
                }
            }
            buttonTransition.updateFrame(node: buttonNode, frame: button.frame, delay: buttonDelay)
            buttonNode.update(size: button.frame.size, content: buttonContent, text: buttonText, transition: buttonTransition)
            buttonNode.accessibilityLabel = buttonAccessibilityLabel
            buttonNode.accessibilityValue = buttonAccessibilityValue
            buttonNode.accessibilityTraits = buttonAccessibilityTraits
            
            if animateButtonIn {
                buttonNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
            }
        }
        
        var removedKeys: [ButtonDescription.Key] = []
        for (key, button) in self.buttonNodes {
            if !validKeys.contains(key) {
                removedKeys.append(key)
                if animated {
                    if case .decline = key {
                        transition.updateTransformScale(node: button, scale: 0.1)
                        transition.updateAlpha(node: button, alpha: 0.0, completion: { [weak button] _ in
                            button?.removeFromSupernode()
                        })
                    } else {
                        transition.updateAlpha(node: button, alpha: 0.0, completion: { [weak button] _ in
                            button?.removeFromSupernode()
                        })
                    }
                } else {
                    button.removeFromSupernode()
                }
            }
        }
        for key in removedKeys {
            self.buttonNodes.removeValue(forKey: key)
        }
        
        return height
    }
    
    @objc func buttonPressed(_ button: ContestCallButtonNode) {
        for (key, listButton) in self.buttonNodes {
            if button === listButton {
                switch key {
                case .accept:
                    self.acceptOrEnd?()
                case .acceptOrEnd:
                    self.acceptOrEnd?()
                case .decline:
                    self.decline?()
                case .enableCamera:
                    self.toggleVideo?()
                case .switchCamera:
                    self.rotateCamera?()
                case .soundOutput:
                    self.speaker?()
                case .mute:
                    self.mute?()
                }
                break
            }
        }
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for (_, button) in self.buttonNodes {
            if let result = button.view.hitTest(self.view.convert(point, to: button.view), with: event) {
                return result
            }
        }
        
        return super.hitTest(point, with: event)
    }
}
