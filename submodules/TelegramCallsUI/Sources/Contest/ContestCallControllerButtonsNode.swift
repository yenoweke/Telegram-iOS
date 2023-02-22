import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import MediaPlayer
import TelegramPresentationData

private let largeButtonSize: CGFloat = 56.0

final class ContestCallControllerButtonsNode: ASDisplayNode, CallControllerButtonsNodeProtocol {
    
    private var buttonNodes: [ButtonDescription.Key: ContestCallButtonNode] = [:]
    private var mode: CallControllerButtonsMode?
    
    var isMuted = false
    
    var acceptOrEnd: (() -> Void)?
    var decline: (() -> Void)?
    var mute: (() -> Void)?
    var speaker: (() -> Void)?
    var toggleVideo: (() -> Void)?
    var rotateCamera: (() -> Void)?
    
    func videoButtonFrame() -> CGRect? {
        return self.buttonNodes[.enableCamera]?.frame
    }

    override init() {
        super.init()
    }

    var strings: PresentationStrings?
    
    func updateLayout(strings: PresentationStrings, mode: CallControllerButtonsMode, constrainedWidth: CGFloat, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGFloat {
        
        let buttonsTransition: ContainedViewLayoutTransition
        if transition.isAnimated {
            buttonsTransition = .animated(duration: 0.3, curve: .spring)
        } else {
            buttonsTransition = .immediate
        }
    
        self.strings = strings
        self.mode = mode
        
        var buttonsDescription: [ButtonDescription] = []
        
        let speakerMode: CallControllerButtonsSpeakerMode
        let videoState: CallControllerButtonsMode.VideoState
        let hasAudioRouteMenu: Bool
        switch mode {
        case .incoming(let speakerModeValue, let hasAudioRouteMenuValue, let videoStateValue), .outgoingRinging(let speakerModeValue, let hasAudioRouteMenuValue, let videoStateValue), .active(let speakerModeValue, let hasAudioRouteMenuValue, let videoStateValue):
            speakerMode = speakerModeValue
            videoState = videoStateValue
            hasAudioRouteMenu = hasAudioRouteMenuValue
        }
        
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
        // TODO: if video call, first shoud be flip camera button
        buttonsDescription.append(.soundOutput(soundOutput))
        
        let isCameraActive: Bool
        let isScreencastActive: Bool
        var isCameraEnabled: Bool
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
        
        switch mode {
        case .outgoingRinging, .incoming:
            isCameraEnabled = false
        case .active:
            break
        }
            
        buttonsDescription.append(.enableCamera(isActive: isCameraActive || isScreencastActive, isEnabled: isCameraEnabled, isLoading: isCameraInitializing, isScreencast: isScreencastActive))
        
        if hasAudioRouteMenu {
//             TODO: how it works?
//            topButtons.append(.soundOutput(soundOutput))
            buttonsDescription.append(.mute(self.isMuted))
        } else {
            buttonsDescription.append(.mute(self.isMuted))
        }
        buttonsDescription.append(.end(.cancel))
        
        var buttons: [ContestCallButtonNode] = []
        
        for description in buttonsDescription {
            let button = makeButtonIfNeeded(for: description.key)
            buttons.append(button)
        }
        
        let horizontalInset: CGFloat = 30.5
        let buttonSpacing: CGFloat
        if buttons.count > 1 {
            let count: CGFloat = CGFloat(buttons.count)
            buttonSpacing = (constrainedWidth - 2 * horizontalInset - count * largeButtonSize) / (count - 1)
        } else {
            buttonSpacing = 0.0
        }

        var buttonFrame = CGRect(x: horizontalInset, y: 0.0, width: largeButtonSize, height: largeButtonSize)
        for button in buttons {
            button.frame = buttonFrame
            buttonFrame.origin.x += largeButtonSize + buttonSpacing
        }
        
        for description in buttonsDescription {
            let button = makeButtonIfNeeded(for: description.key)
            let (buttonContent, buttonText, _, _, _) = makeButtonContent(description, strings, forContest: true)
            button.update(text: buttonText, content: buttonContent, transition: buttonsTransition)
        }

        let existingKeys = Set(buttonsDescription.map(\.key))
        for (key, button) in self.buttonNodes where existingKeys.contains(key) == false {
            transition.updateTransformScale(node: button, scale: 0.1)
            transition.updateAlpha(node: button, alpha: 0.0, completion: { [weak button] _ in
                button?.removeFromSupernode()
            })
            self.buttonNodes.removeValue(forKey: key)
        }
        let textAndSpaceHeight: CGFloat = 20.0
        return largeButtonSize + max(bottomInset + textAndSpaceHeight + 32.0, 46.0)
    }
    
    func makeButtonIfNeeded(for key: ButtonDescription.Key) -> ContestCallButtonNode {
        if let button = self.buttonNodes[key] {
            return button
        } else {
            let buttonNode = ContestCallButtonNode()
            self.buttonNodes[key] = buttonNode
            self.addSubnode(buttonNode)
            buttonNode.addTarget(self, action: #selector(self.buttonPressed(_:)), forControlEvents: .touchUpInside)
            return buttonNode
        }
    }
    
    var toggleIt = true

    @objc private func buttonPressed(_ button: ContestCallButtonNode) {
        for (key, listButton) in self.buttonNodes where button === listButton {
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
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for (_, button) in self.buttonNodes {
            if let result = button.view.hitTest(self.view.convert(point, to: button.view), with: event) {
                return result
            }
        }
        
        return super.hitTest(point, with: event)
    }

}
