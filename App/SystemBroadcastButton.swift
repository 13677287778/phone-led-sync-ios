import SwiftUI
import ReplayKit

struct SystemBroadcastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let view = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 52, height: 52))
        view.preferredExtension = (Bundle.main.bundleIdentifier ?? "com.colorlight.ledsync") + ".Broadcast"
        view.showsMicrophoneButton = false
        view.tintColor = .white
        view.accessibilityLabel = "打开系统屏幕广播"
        return view
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
