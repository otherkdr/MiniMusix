import Foundation
import Combine
import CoreAudio
import CoreBluetooth

enum AudioOutputDeviceKind: Equatable {
    case bluetooth
    case airPlay
    case builtIn
    case external
    case unknown

    var iconName: String {
        switch self {
        case .bluetooth:
            return "headphones"
        case .airPlay:
            return "airplayaudio"
        case .builtIn:
            return "speaker.wave.2.fill"
        case .external:
            return "hifispeaker.2.fill"
        case .unknown:
            return "speaker.fill"
        }
    }

    static func iconName(for deviceName: String, kind: AudioOutputDeviceKind) -> String {
        let name = deviceName.lowercased()

        if name.contains("airpods") || name.contains("buds") || name.contains("earbud") || name.contains("earpods") {
            return "earbuds"
        }

        if name.contains("headphone") || name.contains("headset") || name.contains("beats") || name.contains("sony") || name.contains("bose") {
            return "headphones"
        }

        if name.contains("homepod") {
            return "homepod.fill"
        }

        if name.contains("tv") || name.contains("display") || name.contains("monitor") {
            return "tv.fill"
        }

        if name.contains("hdmi") {
            return "rectangle.connected.to.line.below"
        }

        if name.contains("usb") || name.contains("interface") || name.contains("dac") {
            return "cable.connector"
        }

        if name.contains("speaker") || name.contains("soundbar") {
            return "hifispeaker.fill"
        }

        return kind.iconName
    }
}

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let kind: AudioOutputDeviceKind
    let isDefault: Bool

    var isWireless: Bool {
        kind == .bluetooth || kind == .airPlay
    }

    var iconName: String {
        AudioOutputDeviceKind.iconName(for: name, kind: kind)
    }
}

struct NearbyWirelessDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isConnectable: Bool

    var iconName: String {
        AudioOutputDeviceKind.iconName(for: name, kind: .bluetooth)
    }
}

@MainActor
final class AudioOutputDeviceMonitor: NSObject, ObservableObject {
    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var defaultDevice: AudioOutputDevice?
    @Published private(set) var connectedDevice: AudioOutputDevice?
    @Published private(set) var nearbyWirelessDevices: [NearbyWirelessDevice] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false

    private let audioQueue = DispatchQueue(label: "com.minimusix.audio-output-device-monitor")
    private var isMonitoring = false
    private var loadTask: Task<Void, Never>?
    private var scanStopTask: Task<Void, Never>?
    private var centralManager: CBCentralManager?
    private var nearbyDeviceNamesByID: [UUID: String] = [:]
    private var hasDefaultDeviceBaseline = false

    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        Task { @MainActor [weak self] in
            self?.refreshDevices()
        }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        addHardwareListeners()
        refreshDevices(revealingConnection: false)
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        loadTask?.cancel()
        scanStopTask?.cancel()
        centralManager?.stopScan()
        isLoading = false
        connectedDevice = nil
        nearbyWirelessDevices = []
        nearbyDeviceNamesByID = [:]
        hasDefaultDeviceBaseline = false
        removeHardwareListeners()
    }

    func loadDevices() {
        startMonitoring()
        loadTask?.cancel()
        isLoading = true

        beginNearbyScan()

        loadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.refreshDevices()
                self?.hasLoaded = true
                self?.isLoading = false
            }
        }
    }

    func refreshDevices(revealingConnection: Bool = true) {
        let previousDefaultID = defaultDevice?.id
        let defaultID = Self.defaultOutputDeviceID()
        let nextDevices = Self.allOutputDevices(defaultID: defaultID)
        devices = nextDevices.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && !rhs.isDefault
            }

            if lhs.isWireless != rhs.isWireless {
                return lhs.isWireless && !rhs.isWireless
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        let nextDefaultDevice = nextDevices.first { $0.id == defaultID }
        defaultDevice = nextDefaultDevice

        guard revealingConnection, hasDefaultDeviceBaseline else {
            hasDefaultDeviceBaseline = true
            return
        }

        if previousDefaultID != defaultID, let nextDefaultDevice, nextDefaultDevice.isWireless {
            connectedDevice = nextDefaultDevice
        }
    }

    func clearConnectedDevice() {
        connectedDevice = nil
    }

    private func beginNearbyScan() {
        nearbyDeviceNamesByID = [:]
        nearbyWirelessDevices = []

        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        } else if centralManager?.state == .poweredOn {
            startBluetoothScan()
        }
    }

    private func startBluetoothScan() {
        guard centralManager?.state == .poweredOn else { return }
        centralManager?.stopScan()
        centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        scanStopTask?.cancel()
        scanStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.centralManager?.stopScan()
            }
        }
    }

    private func updateNearbyDevice(id: UUID, name: String, isConnectable: Bool) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        nearbyDeviceNamesByID[id] = trimmedName

        let audioOutputNames = Set(devices.map { $0.name.lowercased() })
        nearbyWirelessDevices = nearbyDeviceNamesByID
            .compactMap { id, name in
                audioOutputNames.contains(name.lowercased()) ? nil : NearbyWirelessDevice(id: id, name: name, isConnectable: isConnectable)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func select(_ device: AudioOutputDevice) -> AudioOutputDevice? {
        var deviceID = device.id
        var address = Self.defaultOutputAddress
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &deviceID
        )

        guard status == noErr else {
            refreshDevices(revealingConnection: false)
            return nil
        }

        refreshDevices(revealingConnection: false)
        let connected = defaultDevice?.id == device.id ? defaultDevice : device
        if let connected, connected.isWireless {
            connectedDevice = connected
        }
        return connected
    }

    private func addHardwareListeners() {
        for address in Self.hardwareListenerAddresses {
            var mutableAddress = address
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &mutableAddress,
                audioQueue,
                deviceListener
            )
        }
    }

    private func removeHardwareListeners() {
        for address in Self.hardwareListenerAddresses {
            var mutableAddress = address
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &mutableAddress,
                audioQueue,
                deviceListener
            )
        }
    }

    private static var hardwareListenerAddresses: [AudioObjectPropertyAddress] {
        [
            defaultOutputAddress,
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        ]
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

    private static func allOutputDevices(defaultID: AudioObjectID) -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard hasOutputStreams(deviceID), let name = deviceName(for: deviceID) else { return nil }
            return AudioOutputDevice(
                id: deviceID,
                name: name,
                kind: deviceKind(for: deviceID),
                isDefault: deviceID == defaultID
            )
        }
    }

    private static func hasOutputStreams(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    private static func deviceName(for deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &name
        )
        guard status == noErr, let name else { return nil }
        return name.takeUnretainedValue() as String
    }

    private static func deviceKind(for deviceID: AudioObjectID) -> AudioOutputDeviceKind {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr else { return .unknown }

        switch value {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeAirPlay:
            return .airPlay
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return .external
        default:
            return .unknown
        }
    }
}

extension AudioOutputDeviceMonitor: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.centralManager = central
            if central.state == .poweredOn {
                self.startBluetoothScan()
            } else {
                self.nearbyDeviceNamesByID = [:]
                self.nearbyWirelessDevices = []
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = localName ?? peripheral.name ?? ""
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false

        Task { @MainActor [weak self] in
            self?.updateNearbyDevice(id: peripheral.identifier, name: name, isConnectable: isConnectable)
        }
    }
}
