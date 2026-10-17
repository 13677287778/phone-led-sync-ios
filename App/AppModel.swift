import SwiftUI
import Combine
import CoreBluetooth

@MainActor final class AppModel: ObservableObject {
    @Published var settings = LEDSettings()
    @Published var broadcast = BroadcastStatus()
    @Published var senderState = SenderSnapshot()
    @Published var error: String?
    @Published var hostText = "192.168.4.1"
    @Published var portText = "45679"
    @Published var xPercent = "50"
    @Published var yPercent = "50"
    @Published var scanning = false
    @Published var preparing = false
    @Published var pickerReady = false
    @Published var selectedColor = RGB.black
    @Published var screenshot: UIImage?
    private var sender = ColorSender()
    private var manualColor: RGB?
    private var timer: AnyCancellable?
    private var manualTimer: AnyCancellable?
    private var scanTimeout: AnyCancellable?
    private var runningInForeground = true
    private var preparationStartedAt = 0.0
    private var linkKey: String { "\(settings.mode.rawValue)|\(settings.host)|\(settings.port)|\(settings.peripheralID)" }
    var hasGroup: Bool { SharedStore.root != nil }
    var isBroadcasting: Bool { broadcast.isRunning }
    var currentColor: RGB { isBroadcasting ? broadcast.rgb : selectedColor }

    init() {
        settings = SharedStore.settings(); loadFields()
        timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.poll() }
        refreshPickerReadiness(); poll()
    }
    func loadFields() {
        hostText = settings.host; portText = String(settings.port)
        xPercent = String(format: "%.2f",settings.u*100); yPercent = String(format: "%.2f",settings.v*100)
    }
    @discardableResult func save(normalizeFields: Bool = true, reportError: Bool = true) -> Bool {
        guard let port = Int(portText), let x = Double(xPercent), let y = Double(yPercent) else {
            pickerReady = false
            if reportError { error = "请检查地址、端口和取色位置" }; return false
        }
        var next = settings; next.host = hostText.trimmingCharacters(in: .whitespacesAndNewlines)
        next.port = port; next.u = x/100; next.v = y/100
        guard next.isValid else {
            pickerReady = false
            if reportError { error = next.mode == .ble && UUID(uuidString: next.peripheralID) == nil ? "请先扫描并选择灯板" : "请检查地址、端口及位置" }; return false
        }
        do {
            try SharedStore.write(next, name: "settings.json"); settings = next
            if normalizeFields { loadFields() }
            refreshPickerReadiness(); return true
        }
        catch { pickerReady = false; if reportError { self.error = error.localizedDescription }; return false }
    }
    func saveQuietly() { _ = save(normalizeFields: false, reportError: false) }
    private func refreshPickerReadiness() {
        pickerReady = settings.isValid && hasGroup && manualColor == nil && !scanning &&
            (UserDefaults.standard.string(forKey: "ColorLight.preparedLink") == linkKey ||
             (settings.mode == .ble && CBCentralManager.authorization == .allowedAlways))
    }
    func selectPoint(u: Double, v: Double) {
        settings.u = SampleGeometry.clamp(u); settings.v = SampleGeometry.clamp(v)
        xPercent = String(format: "%.2f",settings.u*100); yPercent = String(format: "%.2f",settings.v*100)
    }
    func choose(_ choice: BLEChoice) {
        settings.peripheralID = choice.id; settings.peripheralName = choice.name
        endManual(); scanning = false; scanTimeout = nil
        if save() { error = nil }
    }
    func scan() {
        guard !SharedStore.status().isRunning else { error = "请先停止同步再扫描蓝牙"; return }
        endManual(); scanning = true; pickerReady = false
        var config = settings; config.mode = .ble
        sender.configure(config, scanOnly: true)
        scanTimeout = Just(0).delay(for: .seconds(12), scheduler: DispatchQueue.main).sink { [weak self] _ in
            self?.scanning = false; self?.sender.stop()
        }
    }
    func test(_ rgb: RGB) {
        guard !SharedStore.status().isRunning else { error = "请先停止同步再测试灯光"; return }
        guard save() else { return }
        scanning = false; scanTimeout = nil
        manualColor = rgb; selectedColor = rgb; pickerReady = false
        sender.configure(settings); sender.offer(rgb, brightness: settings.brightness)
        // Refresh only while this app is foreground, never rely on background timers.
        manualTimer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self, self.runningInForeground, let rgb = self.manualColor else { return }
            self.sender.offer(rgb, brightness: self.settings.brightness)
        }
    }
    func apply() {
        let manual = manualColor
        guard save() else { return }
        if !isBroadcasting, let rgb = manual { test(rgb) }
    }
    func prepareBroadcast() {
        guard !SharedStore.status().isRunning else { return }
        guard save() else { return }
        endManual(); preparing = true
        preparationStartedAt = ProcessInfo.processInfo.systemUptime
        // Cause local-network/Bluetooth permission to be requested IN THE APP,
        // before its broadcast extension is in the background.
        if settings.mode == .wifi { test(.black) }
        else { sender.configure(settings) }
    }
    func releaseForBroadcastPicker() {
        UserDefaults.standard.set(linkKey, forKey: "ColorLight.preparedLink")
        endManual()
        // Explicit hand-off before the user taps the SYSTEM picker, avoiding
        // the containing app retaining the BLE connection needed by extension.
        preparing = false; pickerReady = true
    }
    func stopBroadcast() {
        do { try SharedStore.stop() } catch { self.error = error.localizedDescription }
    }
    func foreground(_ active: Bool) {
        runningInForeground = active
        if !active { endManual() }
        else {
            poll()
            refreshPickerReadiness()
            if preparing && !isBroadcasting {
                if settings.mode == .wifi { test(.black) }
                else { sender.configure(settings) }
            }
        }
    }
    func endManual() {
        manualTimer = nil; manualColor = nil; scanTimeout = nil; scanning = false; sender.stop()
    }
    private func poll() {
        broadcast = SharedStore.status(); senderState = sender.snapshot
        if broadcast.isRunning && manualColor != nil { endManual() }
        if preparing && senderState.ready { releaseForBroadcastPicker() }
        else if preparing && ProcessInfo.processInfo.systemUptime - preparationStartedAt > 12 {
            preparing = false; endManual(); error = "未连接到灯板，请检查蓝牙或 Wi-Fi"
        }
    }
}
