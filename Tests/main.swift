import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    checks += 1
    guard condition() else { fatalError("FAILED: \(description)") }
}
let golden = LEDFrame(rgb: RGB(r: 255,g: 128,b: 7),brightness: 96)
let encoded = golden.encode(session: 0x12345678,sequence: 0x01020304)
check(encoded.map { String(format: "%02x",$0) }.joined() == "434c01607856341204030201ff80071a", "Android/firmware golden vector")
check(encoded.count == 16, "16 bytes")
check(encoded.dropLast().reduce(UInt8(0),^) == encoded.last!, "XOR checksum")
for session in [UInt32(0),1,0x80000000,UInt32.max] {
    for sequence in [UInt32(0),1,UInt32.max] {
        let bytes = [UInt8](golden.encode(session: session,sequence: sequence))
        var a: UInt32 = 0, b: UInt32 = 0
        for i in 0..<4 { a |= UInt32(bytes[4+i]) << UInt32(i*8); b |= UInt32(bytes[8+i]) << UInt32(i*8) }
        check(a == session && b == sequence,"unsigned little-endian")
    }
}
let expected: [(Double,Double)] = [(0.2,0.3),(0.8,0.3),(0.8,0.7),(0.2,0.7),(0.3,0.2),(0.3,0.8),(0.7,0.8),(0.7,0.2)]
for orientation in 1...8 {
    let point = SampleGeometry.rawPoint(u: 0.2,v: 0.3,orientation: UInt32(orientation))
    check(abs(point.0-expected[orientation-1].0)<0.00001 && abs(point.1-expected[orientation-1].1)<0.00001,"EXIF orientation \(orientation)")
}
for w in [1,2,375,750,1170,1440,2048] {
    for h in [1,3,667,1334,2532,3200] {
        for o in UInt32(1)...UInt32(8) {
            for (u,v) in [(-1.0,-1.0),(0,0),(0.5,0.5),(1,1),(2,2)] {
                let (x,y) = SampleGeometry.pixel(u: u,v: v,width: w,height: h,orientation: o)
                check(x>=0 && x<w && y>=0 && y<h,"clamped pixel, any screen size")
            }
        }
    }
}
check(SampleGeometry.clamp(.nan) == 0.5,"NaN clamp")
check(SampleGeometry.yuv(y: 16,cb: 128,cr: 128,full: false,bt709: false) == .black,"limited black")
check(SampleGeometry.yuv(y: 235,cb: 128,cr: 128,full: false,bt709: true) == RGB(r: 255,g: 255,b: 255),"limited white")
check(SampleGeometry.yuv(y: 0,cb: 128,cr: 128,full: true,bt709: true) == .black,"full black")
check(SampleGeometry.yuv(y: 255,cb: 128,cr: 128,full: true,bt709: false) == RGB(r: 255,g: 255,b: 255),"full white")
var config = LEDSettings();check(config.isValid,"default config")
config.host = "bad.host";check(!config.isValid,"no accidental DNS/mobile routing")
config.host = "192.168.4.1";config.port = 65536;check(!config.isValid,"port bounds")
config.port = 45679;config.u = .nan;check(!config.isValid,"invalid sampling location")
config.u = 0.5;config.mode = .ble;check(!config.isValid,"BLE requires saved UUID")
config.peripheralID = UUID().uuidString;check(config.isValid,"valid BLE choice")
let roundTrip = try JSONDecoder().decode(LEDSettings.self,from: JSONEncoder().encode(config))
check(roundTrip == config,"shared settings round trip")
let slot = LatestColorMailbox()
for i in 0..<10000 { slot.offer(LEDFrame(rgb: RGB(r: UInt8(i%256),g: 1,b: 2),brightness: 96),now: Double(i)) }
check(slot.read()?.timestamp == 9999,"no old FIFO backlog")
check(slot.read()?.frame.rgb.r == UInt8(9999%256),"newest color")
slot.clear();check(slot.read() == nil,"stop clears pending color")
let group = DispatchGroup()
for i in 0..<4 { DispatchQueue.global().async(group: group) { for j in 0..<10000 { slot.offer(golden,now: Double(i*10000+j)); _ = slot.read() } } }
group.wait();check(slot.read() != nil,"concurrent producer/read safety")
var pacer = FramePacer()
var accepted = 0
var oldAccepted = 0
var oldLast = -1.0
for i in 0..<600 {
    let jitter = i%3 == 0 ? 0.0 : i%3 == 1 ? 0.0008 : -0.0008
    let now = Double(i)/60 + jitter
    if pacer.accepts(at: now,fps: 60) { accepted += 1 }
    if now-oldLast >= 1.0/60 { oldAccepted += 1; oldLast = now }
}
check(accepted == 600,"60 Hz jitter does not discard alternate callbacks")
check(oldAccepted < accepted,"regression reproduces previous interval-gate drops")
print("Jitter regression: previous gate \(oldAccepted)/600, phase pacer \(accepted)/600 (synthetic callbacks, not phone latency)")
for (input,target) in [(60,30),(120,60),(60,120)] {
    pacer.reset(); var n = 0
    for i in 0..<input*10 { if pacer.accepts(at: Double(i)/Double(input),fps: target) { n += 1 } }
    check(n == min(input,target)*10,"phase pacer rate \(input)->\(target)")
}
check(!pacer.accepts(at: .nan,fps: 60),"invalid pacer time")
pacer.reset();check(pacer.accepts(at: 0,fps: 60),"first frame")
check(!pacer.accepts(at: 0.001,fps: 60),"reject burst")
check(pacer.accepts(at: 10,fps: 60),"skip missed schedule slots")
check(!pacer.accepts(at: 10.001,fps: 60),"no catch-up FIFO")
check(pacer.accepts(at: 10.002,fps: 120),"rate change resets phase")
var meter = PipelineMeter()
check(meter.summary == nil,"no fabricated zero latency before measurements")
for i in 1...300 { meter.record(sampleMS: 0.1,submitMS: Double(i)) }
let timing = meter.summary!
check(timing.count == 120,"bounded timing window")
check(abs(timing.averageSubmitMS-240.5)<0.00001,"recent-window mean")
check(timing.p95SubmitMS == 294 && timing.submitMS == 300,"recent-window percentile/latest")
meter.record(sampleMS: -1,submitMS: 0);meter.record(sampleMS: 2,submitMS: 1);meter.record(sampleMS: 0,submitMS: .nan)
check(meter.summary?.submitMS == 300,"reject invalid measurement")
slot.offer(golden,now: 10,capturedAt: 9.99,samplingMS: 0.25)
check(slot.read()?.capturedAt == 9.99 && slot.read()?.samplingMS == 0.25,"timing travels with newest color")
let encodedTiming = try JSONEncoder().encode(timing)
let decodedTiming = try JSONDecoder().decode(PipelineTiming.self,from: encodedTiming)
check(decodedTiming.count == 120,"timing status JSON")
let pcGolden = ComputerColorPacket.encode(sequence: 13,sampledNanoseconds: 8423492612000,rgb: RGB(r: 128,g: 64,b: 255))
check(String(decoding: pcGolden,as: UTF8.self)=="C1,13,8423492612000,128,64,255\n","original PC C1 golden protocol")
check(ComputerColorPacket.nanoseconds(1.25)==1_250_000_000,"PC monotonic timestamp units")
check(ComputerColorPacket.nanoseconds(.nan)==0 && ComputerColorPacket.nanoseconds(-1)==0,"invalid timestamp safe conversion")
check(ComputerColorPacket.nanoseconds(Double.greatestFiniteMagnitude)==UInt64.max,"timestamp overflow clamp")
let oldJSON = Data(#"{"mode":"ble","peripheralID":"12345678-1234-1234-1234-123456789012","u":0.8276,"v":0.4342,"brightness":96}"#.utf8)
var upgraded = try JSONDecoder().decode(LEDSettings.self,from: oldJSON)
check(upgraded.target == .light && upgraded.isValid,"old settings migrate without losing BLE device")
check(upgraded.u == 0.8276 && upgraded.v == 0.4342 && upgraded.pcPort == 45678,"preserve existing pick and initialize PC port")
upgraded.target = .computer
check(!upgraded.isValid,"PC needs its own address")
upgraded.pcHost = "192.168.1.100";upgraded.peripheralID = ""
check(upgraded.isValid,"PC does not require BLE hardware")
upgraded.pcPort = 65536;check(!upgraded.isValid,"PC port bounds")
upgraded.pcPort = 45678
let newRoundTrip = try JSONDecoder().decode(LEDSettings.self,from: JSONEncoder().encode(upgraded))
check(newRoundTrip == upgraded,"integrated target settings round trip")
print("PC_GOLDEN " + String(decoding: pcGolden,as: UTF8.self).trimmingCharacters(in: .newlines))
print("PASS \(checks) Swift core checks; screen-to-light latency not measured")
