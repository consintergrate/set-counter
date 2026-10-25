import CoreBluetooth
import Foundation

/// Standard Bluetooth LE heart rate sensors (Polar, Garmin, Wahoo straps, armbands...).
@MainActor
@Observable
final class BluetoothHeartRate: NSObject {
    static let shared = BluetoothHeartRate()

    nonisolated(unsafe) private static let heartRateService = CBUUID(string: "180D")
    nonisolated(unsafe) private static let heartRateMeasurement = CBUUID(string: "2A37")
    private static let savedIDKey = "heartRatePeripheralID"

    private(set) var isPoweredOn = false
    private(set) var isScanning = false
    private(set) var discovered: [CBPeripheral] = []
    private(set) var connected: CBPeripheral?
    private(set) var connecting: CBPeripheral?

    @ObservationIgnored private var central: CBCentralManager?

    private var savedID: UUID? {
        get { UserDefaults.standard.string(forKey: Self.savedIDKey).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Self.savedIDKey) }
    }

    var hasSavedSensor: Bool { savedID != nil }

    /// Creating the manager shows the Bluetooth permission prompt the first time.
    func activate() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        activate()
        guard let central, isPoweredOn else { return }
        discovered = central.retrieveConnectedPeripherals(withServices: [Self.heartRateService])
        central.scanForPeripherals(withServices: [Self.heartRateService])
        isScanning = true
    }

    func stopScan() {
        central?.stopScan()
        isScanning = false
    }

    func connect(_ peripheral: CBPeripheral) {
        stopScan()
        if let connected, connected != peripheral { central?.cancelPeripheralConnection(connected) }
        savedID = peripheral.identifier
        connecting = peripheral
        central?.connect(peripheral)
    }

    func forget() {
        savedID = nil
        for peripheral in [connected, connecting].compactMap({ $0 }) {
            central?.cancelPeripheralConnection(peripheral)
        }
        connected = nil
        connecting = nil
    }

    private func reconnectSaved() {
        guard let central, let savedID,
              let peripheral = central.retrievePeripherals(withIdentifiers: [savedID]).first else { return }
        connecting = peripheral
        central.connect(peripheral)
    }

    private func handle(_ peripheral: CBPeripheral, measurement data: Data) {
        guard let bpm = Self.parse(data) else { return }
        HeartRateMonitor.shared.report(bpm, source: peripheral.name ?? String(localized: "심박 센서"))
    }

    /// Heart Rate Measurement (0x2A37): flag bit 0 selects UInt8 or little-endian UInt16.
    static func parse(_ data: Data) -> Int? {
        let bytes = [UInt8](data)
        guard let flags = bytes.first else { return nil }
        if flags & 0x01 == 0 {
            return bytes.count > 1 ? Int(bytes[1]) : nil
        }
        return bytes.count > 2 ? Int(bytes[1]) | Int(bytes[2]) << 8 : nil
    }
}

// The central manager is created on the main queue, so callbacks arrive on the main thread.
extension BluetoothHeartRate: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            isPoweredOn = central.state == .poweredOn
            if isPoweredOn { reconnectSaved() } else { isScanning = false }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            if !discovered.contains(peripheral) { discovered.append(peripheral) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            connecting = nil
            connected = peripheral
            peripheral.delegate = self
            peripheral.discoverServices([Self.heartRateService])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        MainActor.assumeIsolated {
            if connecting == peripheral { connecting = nil }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        MainActor.assumeIsolated {
            if connected == peripheral { connected = nil }
            // Keep trying while the sensor is still the saved one (e.g. it went out of range).
            if peripheral.identifier == savedID {
                connecting = peripheral
                central.connect(peripheral)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        for service in peripheral.services ?? [] where service.uuid == Self.heartRateService {
            peripheral.discoverCharacteristics([Self.heartRateMeasurement], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.heartRateMeasurement {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard let data = characteristic.value else { return }
        MainActor.assumeIsolated {
            handle(peripheral, measurement: data)
        }
    }
}
