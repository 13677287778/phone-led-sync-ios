import Foundation

struct BroadcastStatus: Codable {
    var active = false
    var paused = false
    var updatedAt = Date().timeIntervalSince1970
    var rgb = RGB.black
    var imageWidth = 0
    var imageHeight = 0
    var sampledFrames: UInt64 = 0
    var submitted: UInt64 = 0
    var message = "待机"
    var lastVideoAt = 0.0
    var timing: PipelineTiming?
    var isRunning: Bool { active && Date().timeIntervalSince1970 - updatedAt < 3 }
}

struct StopRequest: Codable { var requestedAt: Double }

enum SharedStore {
    static var groupID: String { Bundle.main.object(forInfoDictionaryKey: "ColorLightAppGroup") as? String ?? "" }
    private static let container: URL? = {
        guard !groupID.isEmpty, !groupID.contains("$(") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }()
    static var root: URL? { container }
    static func read<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let url = root?.appendingPathComponent(name), let data = try? Data(contentsOf: url), data.count < 64*1024 else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func write<T: Encodable>(_ value: T, name: String) throws {
        guard let root = root else {
            throw NSError(domain: "ColorLight", code: 1, userInfo: [NSLocalizedDescriptionKey: "共享配置不可用。当前组：\(groupID)。请核对主 App 和广播扩展实际签名及描述文件是否共同授权此组。"])
        }
        let data = try JSONEncoder().encode(value)
        try data.write(to: root.appendingPathComponent(name), options: [.atomic])
    }
    static func settings() -> LEDSettings { read("settings.json", as: LEDSettings.self) ?? LEDSettings() }
    static func status() -> BroadcastStatus { read("status.json", as: BroadcastStatus.self) ?? BroadcastStatus() }
    static func stop() throws { try write(StopRequest(requestedAt: Date().timeIntervalSince1970), name: "stop.json") }
}
