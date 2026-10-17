import XCTest
import CoreVideo

final class PixelSamplerTests: XCTestCase {
    func testBGRAChannelsStrideAndAverage() throws {
        var optional: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault,7,5,kCVPixelFormatType_32BGRA,nil,&optional),kCVReturnSuccess)
        let buffer = try XCTUnwrap(optional)
        CVPixelBufferLockBaseAddress(buffer,[])
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        memset(base,0xee,stride*5)
        for y in 0..<5 { for x in 0..<7 {
            let offset = y*stride+x*4
            base[offset] = UInt8(x);base[offset+1] = UInt8(y);base[offset+2] = UInt8(x+y);base[offset+3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(buffer,[])
        var s = LEDSettings();s.u = 1;s.v = 1
        XCTAssertEqual(PixelSampler.sample(buffer,settings: s,orientation: 1),RGB(r: 10,g: 4,b: 6))
        s.u = 0;s.v = 0;s.area = 5
        XCTAssertEqual(PixelSampler.sample(buffer,settings: s,orientation: 1),RGB(r: 2,g: 1,b: 1))
        s.area = 1
        XCTAssertEqual(PixelSampler.sample(buffer,settings: s,orientation: 6),RGB(r: 4,g: 4,b: 0))
    }
    func testVideoRangeNV12() throws {
        var optional: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault,4,4,kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,nil,&optional),kCVReturnSuccess)
        let buffer = try XCTUnwrap(optional)
        CVPixelBufferLockBaseAddress(buffer,[])
        let y = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(buffer,0))
        let uv = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(buffer,1))
        memset(y,235,CVPixelBufferGetBytesPerRowOfPlane(buffer,0)*4)
        memset(uv,128,CVPixelBufferGetBytesPerRowOfPlane(buffer,1)*2)
        CVPixelBufferUnlockBaseAddress(buffer,[])
        XCTAssertEqual(PixelSampler.sample(buffer,settings: LEDSettings(),orientation: 1),RGB(r: 255,g: 255,b: 255))
    }
    func testDeviceProtocolGolden() {
        let bytes = LEDFrame(rgb: RGB(r: 255,g: 128,b: 7),brightness: 96).encode(session: 0x12345678,sequence: 0x01020304)
        XCTAssertEqual(bytes.map { String(format: "%02x",$0) }.joined(),"434c01607856341204030201ff80071a")
    }
}
