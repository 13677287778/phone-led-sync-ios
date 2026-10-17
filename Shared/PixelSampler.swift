import CoreVideo
import CoreMedia
import ImageIO

enum PixelSampler {
    static func sample(_ buffer: CVPixelBuffer, settings: LEDSettings, orientation: UInt32) -> RGB? {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return nil }
        let (x,y) = SampleGeometry.pixel(u: settings.u, v: settings.v, width: width, height: height, orientation: orientation)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let radius = settings.area == 5 ? 2 : 0
        let matrix = CVBufferCopyAttachment(buffer, kCVImageBufferYCbCrMatrixKey, nil) as? String
        let bt709 = matrix == (kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String)
        var r = 0, g = 0, b = 0, count = 0
        for py in max(0,y-radius)...min(height-1,y+radius) {
            for px in max(0,x-radius)...min(width-1,x+radius) {
                let rgb: RGB
                if format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_32ARGB || format == kCVPixelFormatType_32RGBA {
                    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
                    let stride = CVPixelBufferGetBytesPerRow(buffer)
                    guard stride >= width*4 else { return nil }
                    let p = base.assumingMemoryBound(to: UInt8.self).advanced(by: py*stride+px*4)
                    if format == kCVPixelFormatType_32BGRA { rgb = RGB(r: p[2], g: p[1], b: p[0]) }
                    else if format == kCVPixelFormatType_32ARGB { rgb = RGB(r: p[1], g: p[2], b: p[3]) }
                    else { rgb = RGB(r: p[0], g: p[1], b: p[2]) }
                } else if format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
                    guard CVPixelBufferGetPlaneCount(buffer) == 2,
                          let luma = CVPixelBufferGetBaseAddressOfPlane(buffer,0),
                          let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer,1) else { return nil }
                    let ys = CVPixelBufferGetBytesPerRowOfPlane(buffer,0), cs = CVPixelBufferGetBytesPerRowOfPlane(buffer,1)
                    let uv = chroma.assumingMemoryBound(to: UInt8.self).advanced(by: (py/2)*cs+(px/2)*2)
                    rgb = SampleGeometry.yuv(y: luma.assumingMemoryBound(to: UInt8.self)[py*ys+px], cb: uv[0], cr: uv[1], full: format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, bt709: bt709)
                } else { return nil }
                r += Int(rgb.r); g += Int(rgb.g); b += Int(rgb.b); count += 1
            }
        }
        guard count > 0 else { return nil }
        return RGB(r: UInt8(r/count),g: UInt8(g/count),b: UInt8(b/count))
    }
}
