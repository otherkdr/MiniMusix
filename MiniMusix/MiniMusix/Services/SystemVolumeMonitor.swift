import Foundation
import Combine
import CoreAudio

enum SystemVolumeDirection {
    case unchanged
    case up
    case down
}

@MainActor
final class SystemVolumeMonitor: ObservableObject {
    @Published private(set) var level: Double = 0
    @Published private(set) var isMuted = false
    @Published private(set) var direction: SystemVolumeDirection = .unchanged
    @Published private(set) var isVisible = false

    private let audioQueue = DispatchQueue(label: "com.minimusix.system-volume-monitor")
    private var outputDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var hideTask: Task<Void, Never>?
    private var isMonitoring = false
    private var hasBaseline = false

    private lazy var defaultOutputListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        Task { @MainActor [weak self] in
            self?.defaultOutputDeviceDidChange()
        }
    }

    private lazy var volumeListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        Task { @MainActor [weak self] in
            self?.refreshVolume(revealingChange: true)
        }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        addDefaultOutputListener()
        defaultOutputDeviceDidChange(revealingChange: false)
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        hideTask?.cancel()
        isVisible = false
        removeDeviceListeners()
        removeDefaultOutputListener()
    }

    private func defaultOutputDeviceDidChange(revealingChange: Bool = true) {
        removeDeviceListeners()
        outputDeviceID = Self.defaultOutputDeviceID()
        addDeviceListeners()
        refreshVolume(revealingChange: revealingChange)
    }

    private func refreshVolume(revealingChange: Bool) {
        guard outputDeviceID != AudioObjectID(kAudioObjectUnknown) else { return }

        let previousLevel = level
        let previousMuted = isMuted
        let nextLevel = Self.outputVolume(for: outputDeviceID) ?? level
        let nextMuted = Self.outputMuteState(for: outputDeviceID) ?? false

        level = nextLevel
        isMuted = nextMuted

        let changed = abs(nextLevel - previousLevel) > 0.004 || nextMuted != previousMuted
        guard revealingChange, hasBaseline, changed else {
            hasBaseline = true
            return
        }

        if nextLevel > previousLevel {
            direction = .up
        } else if nextLevel < previousLevel {
            direction = .down
        } else {
            direction = .unchanged
        }

        revealTemporarily()
    }

    private func revealTemporarily() {
        hideTask?.cancel()
        isVisible = true
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.isVisible = false
            }
        }
    }

    private func addDefaultOutputListener() {
        var address = Self.defaultOutputAddress
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            audioQueue,
            defaultOutputListener
        )
    }

    private func removeDefaultOutputListener() {
        var address = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            audioQueue,
            defaultOutputListener
        )
    }

    private func addDeviceListeners() {
        guard outputDeviceID != AudioObjectID(kAudioObjectUnknown) else { return }

        for address in Self.volumeAddresses(for: outputDeviceID) + Self.muteAddresses(for: outputDeviceID) {
            var mutableAddress = address
            AudioObjectAddPropertyListenerBlock(
                outputDeviceID,
                &mutableAddress,
                audioQueue,
                volumeListener
            )
        }
    }

    private func removeDeviceListeners() {
        guard outputDeviceID != AudioObjectID(kAudioObjectUnknown) else { return }

        for address in Self.volumeAddresses(for: outputDeviceID) + Self.muteAddresses(for: outputDeviceID) {
            var mutableAddress = address
            AudioObjectRemovePropertyListenerBlock(
                outputDeviceID,
                &mutableAddress,
                audioQueue,
                volumeListener
            )
        }
    }

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func defaultOutputDeviceID() -> AudioObjectID {
        var address = defaultOutputAddress
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr ? deviceID : AudioObjectID(kAudioObjectUnknown)
    }

    private static func outputVolume(for deviceID: AudioObjectID) -> Double? {
        let addresses = volumeAddresses(for: deviceID)
        let values = addresses.compactMap { readFloatProperty($0, from: deviceID) }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +) / Float(values.count))
    }

    private static func outputMuteState(for deviceID: AudioObjectID) -> Bool? {
        let addresses = muteAddresses(for: deviceID)
        let values = addresses.compactMap { readUInt32Property($0, from: deviceID) }
        guard let value = values.first else { return nil }
        return value != 0
    }

    private static func volumeAddresses(for deviceID: AudioObjectID) -> [AudioObjectPropertyAddress] {
        outputPropertyAddresses(
            for: deviceID,
            selector: kAudioDevicePropertyVolumeScalar
        )
    }

    private static func muteAddresses(for deviceID: AudioObjectID) -> [AudioObjectPropertyAddress] {
        outputPropertyAddresses(
            for: deviceID,
            selector: kAudioDevicePropertyMute
        )
    }

    private static func outputPropertyAddresses(
        for deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> [AudioObjectPropertyAddress] {
        let candidates = [
            kAudioObjectPropertyElementMain,
            AudioObjectPropertyElement(1),
            AudioObjectPropertyElement(2)
        ].map {
            AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: $0
            )
        }

        return candidates.filter { address in
            var mutableAddress = address
            return AudioObjectHasProperty(deviceID, &mutableAddress)
        }
    }

    private static func readFloatProperty(
        _ address: AudioObjectPropertyAddress,
        from deviceID: AudioObjectID
    ) -> Float? {
        var mutableAddress = address
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &mutableAddress,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr else { return nil }
        return min(max(value, 0), 1)
    }

    private static func readUInt32Property(
        _ address: AudioObjectPropertyAddress,
        from deviceID: AudioObjectID
    ) -> UInt32? {
        var mutableAddress = address
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &mutableAddress,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr else { return nil }
        return value
    }
}
