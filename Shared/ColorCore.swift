import Foundation

struct RGB: Codable, Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    static let black = RGB(r: 0, g: 0, b: 0)
    var hex: String { String(format: "#%02X%02X%02X", Int(r), Int(g), Int(b)) }
}

struct LEDFrame: Equatable {
    var rgb: RGB
    var brightness: UInt8
    func encode(session: UInt32, sequence: UInt32) -> Data {
        var bytes: [UInt8] = [0x43, 0x4c, 1, brightness]
        for value in [session, sequence] {
            for shift in stride(from: 0, to: 32, by: 8) {
                bytes.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
            }
        }
        bytes += [rgb.r, rgb.g, rgb.b]
        bytes.append(bytes.reduce(UInt8(0), ^))
        return Data(bytes)
    }
}

enum LinkMode: String, Codable, CaseIterable { case wifi, ble }
enum OutputTarget: String, Codable, CaseIterable { case light, computer }

enum ComputerColorPacket {
    static func encode(sequence: UInt32, sampledNanoseconds: UInt64, rgb: RGB) -> Data {
        Data("C1,\(sequence),\(sampledNanoseconds),\(rgb.r),\(rgb.g),\(rgb.b)\n".utf8)
    }
    static func nanoseconds(_ seconds: Double) -> UInt64 {
        guard seconds.isFinite, seconds >= 0 else { return 0 }
        let value = seconds * 1_000_000_000
        return value >= Double(UInt64.max) ? UInt64.max : UInt64(value)
    }
}

struct LEDSettings: Codable, Equatable {
    var target: OutputTarget = .light
    var pcHost = ""
    var pcPort = 45678
    var mode: LinkMode = .wifi
    var host = "192.168.4.1"
    var port = 45679
    var peripheralID = ""
    var peripheralName = ""
    // Relative to the visible (oriented) captured image, not UIKit points.
    var u = 0.5
    var v = 0.5
    var brightness = 96
    var fps = 60
    var area = 1
    init() {}
    enum CodingKeys: String, CodingKey {
        case target, pcHost, pcPort, mode, host, port, peripheralID, peripheralName, u, v, brightness, fps, area
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        target = try c.decodeIfPresent(OutputTarget.self,forKey: .target) ?? .light
        pcHost = try c.decodeIfPresent(String.self,forKey: .pcHost) ?? ""
        pcPort = try c.decodeIfPresent(Int.self,forKey: .pcPort) ?? 45678
        mode = try c.decodeIfPresent(LinkMode.self,forKey: .mode) ?? .wifi
        host = try c.decodeIfPresent(String.self,forKey: .host) ?? "192.168.4.1"
        port = try c.decodeIfPresent(Int.self,forKey: .port) ?? 45679
        peripheralID = try c.decodeIfPresent(String.self,forKey: .peripheralID) ?? ""
        peripheralName = try c.decodeIfPresent(String.self,forKey: .peripheralName) ?? ""
        u = try c.decodeIfPresent(Double.self,forKey: .u) ?? 0.5
        v = try c.decodeIfPresent(Double.self,forKey: .v) ?? 0.5
        brightness = try c.decodeIfPresent(Int.self,forKey: .brightness) ?? 96
        fps = try c.decodeIfPresent(Int.self,forKey: .fps) ?? 60
        area = try c.decodeIfPresent(Int.self,forKey: .area) ?? 1
    }
    static func validIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { UInt8($0) }
        return parts.count == 4 && octets.count == 4 && octets[0] > 0 && octets[0] < 224
    }
    var isValid: Bool {
        let destinationOK = target == .computer ? Self.validIPv4(pcHost) && (1...65535).contains(pcPort) :
            Self.validIPv4(host) && (1...65535).contains(port) && (mode != .ble || UUID(uuidString: peripheralID) != nil)
        return destinationOK && u.isFinite && v.isFinite &&
            (0...1).contains(u) && (0...1).contains(v) && (0...255).contains(brightness) &&
            [30, 60, 120].contains(fps) && [1, 5].contains(area)
    }
}

enum SampleGeometry {
    static func clamp(_ x: Double) -> Double { x.isFinite ? min(1, max(0, x)) : 0.5 }
    // EXIF orientation: inverse transform from displayed image to raw buffer.
    static func rawPoint(u: Double, v: Double, orientation: UInt32) -> (Double, Double) {
        let x = clamp(u), y = clamp(v)
        switch orientation {
        case 2: return (1-x, y)
        case 3: return (1-x, 1-y)
        case 4: return (x, 1-y)
        case 5: return (y, x)
        case 6: return (y, 1-x)
        case 7: return (1-y, 1-x)
        case 8: return (1-y, x)
        default: return (x, y)
        }
    }
    static func pixel(u: Double, v: Double, width: Int, height: Int, orientation: UInt32) -> (Int, Int) {
        let (x,y) = rawPoint(u: u, v: v, orientation: orientation)
        return (min(max(0, width-1), Int((x * Double(max(0, width-1))).rounded())),
                min(max(0, height-1), Int((y * Double(max(0, height-1))).rounded())))
    }
    static func orientedSize(width: Int, height: Int, orientation: UInt32) -> (Int, Int) {
        (5...8).contains(orientation) ? (height,width) : (width,height)
    }
    static func yuv(y: UInt8, cb: UInt8, cr: UInt8, full: Bool, bt709: Bool) -> RGB {
        let l = full ? Double(y) : (Double(y)-16) * 255/219
        let d = (Double(cb)-128) * (full ? 1 : 255/224)
        let e = (Double(cr)-128) * (full ? 1 : 255/224)
        func byte(_ v: Double) -> UInt8 { UInt8(min(255,max(0,Int(v.rounded())))) }
        if bt709 { return RGB(r: byte(l+1.5748*e),g: byte(l-0.187324*d-0.468124*e),b: byte(l+1.8556*d)) }
        return RGB(r: byte(l+1.402*e),g: byte(l-0.344136*d-0.714136*e),b: byte(l+1.772*d))
    }
}

/// One overwriteable slot; acquisition never enqueues a closure per captured frame.
final class LatestColorMailbox {
    struct Entry {
        let frame: LEDFrame
        let timestamp: TimeInterval
        let capturedAt: TimeInterval?
        let samplingMS: Double?
    }
    private let lock = NSLock()
    private var entry: Entry?
    func offer(_ frame: LEDFrame, now: TimeInterval = ProcessInfo.processInfo.systemUptime,
               capturedAt: TimeInterval? = nil, samplingMS: Double? = nil) {
        lock.lock(); entry = Entry(frame: frame, timestamp: now, capturedAt: capturedAt, samplingMS: samplingMS); lock.unlock()
    }
    func read() -> Entry? { lock.lock(); defer { lock.unlock() }; return entry }
    func clear() { lock.lock(); entry = nil; lock.unlock() }
}

/// Keep the sampling phase instead of restarting a full interval after every
/// callback. Small callback jitter must not accidentally halve a 60 Hz stream.
struct FramePacer {
    private var nextDue: Double?
    private var previousFPS = 0
    mutating func reset() { nextDue = nil; previousFPS = 0 }
    mutating func accepts(at now: Double, fps: Int) -> Bool {
        guard now.isFinite, [30,60,120].contains(fps) else { return false }
        let interval = 1 / Double(fps)
        if previousFPS != fps || nextDue == nil {
            previousFPS = fps; nextDue = now + interval; return true
        }
        let due = nextDue!
        guard now >= due - min(0.001, interval * 0.1) else { return false }
        nextDue = now > due + interval ? now + interval : due + interval
        return true
    }
}

struct PipelineTiming: Codable {
    var sampleMS: Double
    var averageSampleMS: Double
    var submitMS: Double
    var averageSubmitMS: Double
    var p95SubmitMS: Double
    var count: Int
}

/// Bounded, O(1) updates; percentile is calculated only for the slow status UI.
/// Measures capture-CALLBACK entry to SEND-API invocation, never LED latency.
struct PipelineMeter {
    private var samples: [(sample: Double, submit: Double)] = []
    private var cursor = 0
    private var sampleSum = 0.0
    private var submitSum = 0.0
    private var last = (sample: 0.0, submit: 0.0)
    mutating func record(sampleMS: Double, submitMS: Double) {
        guard sampleMS.isFinite, submitMS.isFinite, sampleMS >= 0, submitMS >= sampleMS else { return }
        let value = (sample: sampleMS, submit: submitMS)
        if samples.count < 120 { samples.append(value) }
        else {
            sampleSum -= samples[cursor].sample; submitSum -= samples[cursor].submit
            samples[cursor] = value; cursor = (cursor + 1) % 120
        }
        sampleSum += sampleMS; submitSum += submitMS; last = value
    }
    var summary: PipelineTiming? {
        guard !samples.isEmpty else { return nil }
        let values = samples.map { $0.submit }.sorted()
        return PipelineTiming(sampleMS: last.sample, averageSampleMS: sampleSum / Double(samples.count),
            submitMS: last.submit, averageSubmitMS: submitSum / Double(samples.count),
            p95SubmitMS: values[Int(ceil(Double(values.count) * 0.95))-1], count: samples.count)
    }
}
