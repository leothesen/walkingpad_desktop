import Foundation
import SwiftUI
import CoreBluetooth

/// Callback fired once all service discovery is complete.
/// `isWalkingPad` is true if both FE01 (notify) and FE02 (command) characteristics were found.
public typealias WalkingPadFoundCallback = (_ peripheral: BluetoothPeripheral, _ isWalkingPad: Bool) -> Void

/// Wraps a CBPeripheral and handles BLE service/characteristic discovery to identify WalkingPad devices.
///
/// Discovery flow:
/// 1. `discover()` triggers service discovery for the three known WalkingPad service UUIDs
/// 2. For each service, discovers all characteristics
/// 3. Looks for FE01 (notify) and FE02 (command) characteristics
/// 4. Once all services are processed, fires the callback with the identification result
open class BluetoothPeripheral: NSObject, CBPeripheralDelegate {
    /// The three BLE service UUIDs advertised by WalkingPad treadmills.
    /// - 0x180A: Standard Device Information Service
    /// - 00010203-...: WalkingPad proprietary service
    /// - 0xFE00: WalkingPad FE service (contains FE01/FE02 characteristics)
    public static let walkingPadServiceUUIDs = [
        CBUUID.init(string: "0000180a-0000-1000-8000-00805f9b34fb"),
        CBUUID.init(string: "00010203-0405-0607-0809-0a0b0c0d1912"),
        CBUUID.init(string: "0000fe00-0000-1000-8000-00805f9b34fb")
    ]

    public var peripheral: CBPeripheral
    /// FE01 characteristic — receives treadmill status notifications
    public var notifyCharacteristic: CBCharacteristic?
    /// FE02 characteristic — accepts speed/mode/start commands
    public var commandCharacteristic: CBCharacteristic?
    /// Tracks services still awaiting characteristic discovery. Callback fires when empty.
    private var nonDiscoveredServices: [CBService] = []
    private var callback: WalkingPadFoundCallback

    init(peripheral: CBPeripheral, callback: @escaping WalkingPadFoundCallback) {
        self.peripheral = peripheral
        self.callback = callback
    }

    /// Starts BLE service discovery for known WalkingPad service UUIDs.
    public func discover() {
        print("discovering \(self.peripheral.name ?? "unknown")")
        self.peripheral.delegate = self
        self.peripheral.discoverServices(BluetoothPeripheral.walkingPadServiceUUIDs)
    }

    /// Receives discovered services and kicks off characteristic discovery for each.
    /// Note: the `error` parameter is not checked — a failed discovery silently results
    /// in no services, leading to a non-WalkingPad identification.
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            let relevantServices = services.filter({ service in BluetoothPeripheral.walkingPadServiceUUIDs.contains(service.uuid)})
            self.nonDiscoveredServices = relevantServices
            for service in relevantServices {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    /// Inspects each characteristic, looking for FE01 (notify) and FE02 (command).
    /// Once all services have been processed, fires the identification callback.
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        print("Service uuid=\(service.uuid) description=\(service.description)")
        if let characteristics = service.characteristics {
            for characteristic in characteristics {

                let asString = characteristic.uuid.uuidString
                print ("> Characteristic uuid=\(characteristic.uuid) (\(asString)) description=\(characteristic.description) \(characteristic.properties)")

                if (asString.isEqual("FE01")) {
                    peripheral.delegate = self
                    self.notifyCharacteristic = characteristic
                }
                if (asString.isEqual("FE02")) {
                    self.commandCharacteristic = characteristic
                }
            }
        }
        self.nonDiscoveredServices = self.nonDiscoveredServices.filter({ nonDiscoveredService in nonDiscoveredService != service })
        self.notifyIfWalkingPad()
    }

    /// Fires the callback once all services have completed characteristic discovery.
    /// A device is identified as a WalkingPad if both FE01 and FE02 characteristics exist.
    private func notifyIfWalkingPad() {
        if (!self.nonDiscoveredServices.isEmpty) {
            return
        }
        let isWalkingPad = self.commandCharacteristic != nil && self.notifyCharacteristic != nil
        self.callback(self, isWalkingPad)
    }
}
