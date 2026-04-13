import Foundation
import MQTTNIO
import NIO

/// MQTT broker connection settings, loaded from `.walkingpad-client-mqtt.json`.
struct MqttConfiguration: Codable {
    var username: String
    var password: String
    var host: String
    var port: UInt16
    var topic: String
}

/// JSON payload published to the MQTT topic on each state update.
struct MqttData: Codable {
    /// Steps reported by the treadmill in the current session
    var stepsWalkingpad: Int
    /// Accumulated steps for the day (including previous sessions)
    var stepsTotal: Int
    /// Accumulated distance for the day (meters)
    var distanceTotal: Int
    /// Current treadmill speed in km/h
    var speedKmh: Double
}

/// Publishes treadmill state to an MQTT broker for Home Assistant and other home automation tools.
///
/// Configuration is loaded from a JSON file at app data path. If no config file exists,
/// the service silently does nothing. Messages are rate-limited: published only on speed
/// changes or when 30+ seconds have elapsed since the last message.
class MqttService {
    private var client: MQTTClient?
    private var fileSystem: FileSystem
    private var lastMessageTime: Date?
    private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var config: MqttConfiguration?

    init(_ fileSystem: FileSystem) {
        self.fileSystem = fileSystem
    }
    
    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }
    
    func start() {
        guard let config = self.loadConfig() else { return }
        self.config = config
        
        let client = MQTTClient(
            configuration: .init(
                target: .host(config.host, port: Int(config.port)),
                clientId: "WalkingPadClient-\(ProcessInfo().processIdentifier)",
                credentials: config.username.isEmpty ? nil : .init(username: config.username, password: config.password)
            ),
            eventLoopGroupProvider: .shared(eventLoopGroup)
        )
        
        client.connect().flatMap { _ -> EventLoopFuture<Void> in
            appLog("MQTT connected successfully")
            self.client = client
            _ = self.subscribeToTopics(config: config)
            return self.eventLoopGroup.next().makeSucceededFuture(())
        }.whenComplete { result in
            switch result {
            case .success:
                appLog("MQTT connected successfully")
                self.client = client
                self.subscribeToTopics(config: config)
            case .failure(let error):
                appLog("MQTT connection failed: \(error)")
            }
        }
    }
    
    @discardableResult
    private func subscribeToTopics(config: MqttConfiguration) -> EventLoopFuture<Void> {
        guard let client = client else {
            return eventLoopGroup.next().makeFailedFuture(NSError(domain: "MQTT", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"]))
        }
        return client.subscribe(to: [.init(topicFilter: config.topic, qos: .atMostOnce)]).map { _ in }
    }
    
    func stop() {
        try? client?.disconnect().wait()
    }
    
    private func loadConfig() -> MqttConfiguration? {
        guard let mqttConfigRaw = self.loadConfigFile() else { return nil }
        
        do {
            let jsonDecoder = JSONDecoder()
            let decoded = try jsonDecoder.decode(MqttConfiguration.self, from: mqttConfigRaw)
            return decoded
        } catch {
            appLog("error while decoding data source json, \(error)")
            return nil
        }
    }
    
    private func shouldSend(oldState: DeviceState?, newState: DeviceState) -> Bool {
        let oldSpeed = oldState?.speed;
        let newSpeed = newState.speed
        guard let lastMessageTime = self.lastMessageTime else { return true }
        
        if (oldSpeed != newSpeed) {
            return true
        }
        
        let now = Date()
        let passedSeconds = now.timeIntervalSince(lastMessageTime)
        return passedSeconds > 30
    }
    
    public func publish(oldState: DeviceState?, newState: DeviceState, workoutState: WorkoutState) {
        guard let client = self.client else { return }
        if (!shouldSend(oldState: oldState, newState: newState)) {
            return
        }
        
        do {
            let jsonData = try JSONEncoder().encode(MqttData(
                stepsWalkingpad: newState.steps,
                stepsTotal: workoutState.steps,
                distanceTotal: workoutState.distance,
                speedKmh: newState.speedKmh()
            ))
            
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            appLog("Publishing MQTT data: \(jsonString)")
            
            client.publish(
                .string(jsonString),
                to: self.config?.topic ?? "walkingpad/stats",
                qos: .atMostOnce
            )
            
            self.lastMessageTime = Date()
        } catch {
            appLog("error while encoding mqtt data, \(error)")
        }
    }
    
    private func loadConfigFile() -> Data? {
        return self.fileSystem.load(filename: ".walkingpad-client-mqtt.json")
    }
}
