import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

struct ScreenshotPicker: UIViewControllerRepresentable {
    var completed: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completed) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1; config.filter = .images
        let picker = PHPickerViewController(configuration: config); picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completed: (UIImage?) -> Void
        init(_ completed: @escaping (UIImage?) -> Void) { self.completed = completed }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else { completed(nil); return }
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, _ in
                guard let url = url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                    DispatchQueue.main.async { self?.completed(nil) }; return
                }
                // Downsample before decoding, apply EXIF rotation, and keep image
                // in RAM only. The extension never receives the screenshot file.
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048,
                    kCGImageSourceShouldCacheImmediately: true]
                let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
                DispatchQueue.main.async { self?.completed(image) }
            }
        }
    }
}

struct ScreenshotPointView: View {
    let image: UIImage
    @Binding var u: Double
    @Binding var v: Double
    var body: some View {
        GeometryReader { geo in
            let factor = min(geo.size.width/image.size.width, geo.size.height/image.size.height)
            let w = image.size.width*factor, h = image.size.height*factor
            let left = (geo.size.width-w)/2, top = (geo.size.height-h)/2
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.04)
                Image(uiImage: image).resizable().frame(width: w, height: h).offset(x: left, y: top)
                Circle().stroke(Color.white, lineWidth: 3).background(Circle().stroke(Color.black,lineWidth: 5))
                    .frame(width: 22,height: 22).position(x: left+w*u,y: top+h*v)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard w > 0, h > 0, value.location.x >= left, value.location.x <= left+w,
                      value.location.y >= top, value.location.y <= top+h else { return }
                u = SampleGeometry.clamp(Double((value.location.x-left)/w))
                v = SampleGeometry.clamp(Double((value.location.y-top)/h))
            })
        }
        .accessibilityLabel("拖动十字圈选择取色位置")
    }
}
