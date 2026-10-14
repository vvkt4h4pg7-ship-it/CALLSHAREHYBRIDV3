import Foundation
import CallKit
import AVFoundation

final class CallKitManager: NSObject {
    private let provider: CXProvider
    private var currentUUID: UUID?
    private var answerAction: CXAnswerCallAction?

    var onStart: ((String) -> Void)?
    var onAnswer: (() -> Void)?
    var onEnd: (() -> Void)?
    var onMute: ((Bool) -> Void)?
    var onDTMF: ((String) -> Void)?
    var onAudioActivated: (() -> Void)?
    var onAudioDeactivated: (() -> Void)?
    var onPrepareAudio: (() -> Void)?
    var onLog: ((String) -> Void)?

    // Keep only a generic failure state. The autoclosure is not evaluated, so
    // interpolation/userInfo formatting never runs and no live log is retained.
    private func reportCriticalError(_ message: @autoclosure () -> String) {
        onLog?("CallKit error")
    }
    private func discardDiagnostic(_ message: @autoclosure () -> String) { }

    override init() {
        let configuration = CXProviderConfiguration(localizedName: "J7Bridge")
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber]
        configuration.includesCallsInRecents = true
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    func reportIncoming(number: String, callerName: String?) {
        guard currentUUID == nil else {
            discardDiagnostic("[CALLKIT] duplicate incoming ignored")
            return
        }
        let uuid = UUID()
        currentUUID = uuid

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: number)
        update.localizedCallerName = callerName
        update.hasVideo = false
        update.supportsDTMF = true
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false

        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if let error {
                let nsError = error as NSError
                self?.reportCriticalError("[CALLKIT] ERROR domain=\(nsError.domain) code=\(nsError.code)")
                self?.reportCriticalError("[CALLKIT] ERROR description=\(nsError.localizedDescription)")
                self?.reportCriticalError("[CALLKIT] ERROR userInfo=\(nsError.userInfo)")
                self?.currentUUID = nil
            } else {
                self?.discardDiagnostic("[CALLKIT] INCOMING UI REPORTED UUID=\(uuid.uuidString)")
            }
        }
    }

    func startOutgoing(number: String) {
        let uuid = UUID()
        currentUUID = uuid
        let handle = CXHandle(type: .phoneNumber, value: number)
        let action = CXStartCallAction(call: uuid, handle: handle)
        action.isVideo = false
        let transaction = CXTransaction(action: action)
        CXCallController().request(transaction) { [weak self] error in
            if let error {
                self?.reportCriticalError("[CALLKIT] start outgoing failed: \(error.localizedDescription)")
                self?.currentUUID = nil
            } else {
                self?.discardDiagnostic("[CALLKIT] OUTGOING transaction accepted UUID=\(uuid.uuidString)")
            }
        }
    }

    func endCurrentCall() {
        guard let uuid = currentUUID else { return }
        let transaction = CXTransaction(action: CXEndCallAction(call: uuid))
        CXCallController().request(transaction) { [weak self] error in
            if let error { self?.reportCriticalError("[CALLKIT] local end failed: \(error.localizedDescription)") }
        }
    }

    func fulfillAnswerIfNeeded() {
        answerAction?.fulfill()
        answerAction = nil
    }

    func reportOutgoingConnecting() {
        guard let uuid = currentUUID else { return }
        provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())
    }

    func reportOutgoingConnected() {
        guard let uuid = currentUUID else { return }
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
    }

    func reportRemoteEnd(reason: CXCallEndedReason = .remoteEnded) {
        guard let uuid = currentUUID else { return }
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
        currentUUID = nil
        answerAction = nil
        onAudioDeactivated?()
    }

    func clearCurrentCall() {
        currentUUID = nil
        answerAction = nil
    }
}

extension CallKitManager: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        currentUUID = nil
        answerAction = nil
        onAudioDeactivated?()
        discardDiagnostic("[CALLKIT] provider reset")
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        currentUUID = action.callUUID
        onPrepareAudio?()
        discardDiagnostic("[CALLSHARE_AUDIO_R1] PREPARE before CallKit activation (outgoing)")
        reportOutgoingConnecting()
        discardDiagnostic("[CALLKIT] START action -> BLE MAKE CALL")
        onStart?(action.handle.value)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        answerAction = action
        onPrepareAudio?()
        discardDiagnostic("[CALLSHARE_AUDIO_R1] PREPARE before CallKit activation (answer)")
        discardDiagnostic("[CALLKIT] ANSWER action -> BLE 05; waiting for K7 05")
        onAnswer?()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        discardDiagnostic("[CALLKIT] END action -> BLE 04")
        onEnd?()
        action.fulfill()
        currentUUID = nil
        answerAction = nil
        onAudioDeactivated?()
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        action.fail()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        onMute?(action.isMuted)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        onDTMF?(action.digits)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        discardDiagnostic("[CALLSHARE_AUDIO_R1] didActivate CALLED")
        discardDiagnostic("[CALLSHARE_AUDIO_R1] session category=\(audioSession.category.rawValue)")
        discardDiagnostic("[CALLSHARE_AUDIO_R1] session mode=\(audioSession.mode.rawValue)")
        discardDiagnostic("[CALLSHARE_AUDIO_R1] sampleRate=\(audioSession.sampleRate)")
        discardDiagnostic("[CALLSHARE_AUDIO_R1] inputChannels=\(audioSession.inputNumberOfChannels)")
        discardDiagnostic("[CALLSHARE_AUDIO_R1] outputChannels=\(audioSession.outputNumberOfChannels)")
        discardDiagnostic("[CALLSHARE_AUDIO_R1] ioBuffer=\(audioSession.ioBufferDuration)")
        let route = audioSession.currentRoute
        let inputs = route.inputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
        let outputs = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
        discardDiagnostic("[CALLSHARE_AUDIO_R1] route IN[\(inputs)] OUT[\(outputs)]")
        discardDiagnostic("[CALLSHARE_AUDIO_R1] hardwareSampleRate=\(audioSession.sampleRate)")
        discardDiagnostic("[CALLKIT] audio session ACT")
        onAudioActivated?()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        discardDiagnostic("[CALLSHARE_AUDIO_R1] didDeactivate CALLED")
        discardDiagnostic("[CALLKIT] audio session DEACT")
        onAudioDeactivated?()
    }
}
