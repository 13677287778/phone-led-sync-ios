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
print("PASS \(checks) Swift core checks; screen-to-light latency not measured")
