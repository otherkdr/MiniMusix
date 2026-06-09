import Foundation
import CoreBluetooth

@MainActor
final class BluetoothPermissionRequester: NSObject, CBCentralManagerDelegate {
    var onPermissionChanged: ((BackendPermissionState) -> Void)?

    private var centralManager: CBCentralManager?

    func requestPermission() {
        updatePermissionState()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func refreshPermissionState() {
        updatePermissionState()
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            self?.centralManager = central
            self?.updatePermissionState(for: central.state)
        }
    }

    private func updatePermissionState(for state: CBManagerState? = nil) {
        switch CBCentralManager.authorization {
        case .allowedAlways:
            if let state {
                switch state {
                case .poweredOn:
                    onPermissionChanged?(.ready)
                case .poweredOff:
                    onPermissionChanged?(.unavailable("Bluetooth is turned off."))
                case .unsupported:
                    onPermissionChanged?(.unavailable("This Mac does not support Bluetooth."))
                case .unauthorized:
                    onPermissionChanged?(.unavailable("Bluetooth access is denied in Privacy & Security."))
                case .resetting:
                    onPermissionChanged?(.unknown)
                case .unknown:
                    onPermissionChanged?(.unknown)
                @unknown default:
                    onPermissionChanged?(.unknown)
                }
            } else {
                onPermissionChanged?(.ready)
            }
        case .denied:
            onPermissionChanged?(.unavailable("Bluetooth access is denied in Privacy & Security."))
        case .restricted:
            onPermissionChanged?(.unavailable("Bluetooth access is restricted on this Mac."))
        case .notDetermined:
            onPermissionChanged?(.unknown)
        @unknown default:
            onPermissionChanged?(.unknown)
        }
    }
}
