import ReplayKit
import CoreMedia
import CoreVideo
import ImageIO

/// Receives frames locally. Audio is ignored; no video file or remote stream.
final class SampleHandler: RPBroadcastSampleHandler {
    private let queue = DispatchQueue(label: "ColorLight.broadcastState")
    private let stateLock = NSLock()
    private var config = LEDSettings()
    private let sender = ColorSender()
    private var status = BroadcastStatus()
    private var ticker: DispatchSourceTimer?
    private var beganAt = 0.0
    private var lastSampleAt = 0.0
    private var ending = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard SharedStore.root != nil else { fail("共享容器不可用，请核对两个目标的 App Groups 签名"); return }
        let loaded = SharedStore.settings()
        guard loaded.isValid else { fail("请先在取色点灯 App 中保存有效设置"); return }
        stateLock.lock(); config = loaded; beganAt = Date().timeIntervalSince1970
        status = BroadcastStatus(); status.active = true; status.message = "等待屏幕画面"; ending = false; stateLock.unlock()
        sender.configure(loaded, keepStaticColor: true)
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(400), leeway: .milliseconds(30))
        source.setEventHandler { [weak self] in self?.maintenance() }
        ticker = source; source.resume()
    }
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        stateLock.lock()
        let c = config, paused = status.paused || ending
        let now = ProcessInfo.processInfo.systemUptime
        let due = now-lastSampleAt >= 1/Double(c.fps)
        if due { lastSampleAt = now }
        stateLock.unlock()
        guard !paused, due, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let attached = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber
        let orientation = attached?.uint32Value ?? 1
        guard let rgb = PixelSampler.sample(buffer, settings: c, orientation: orientation) else {
            stateLock.lock(); status.message = "当前画面格式暂不支持"; stateLock.unlock(); return
        }
        sender.offer(rgb, brightness: c.brightness)
        let (w,h) = SampleGeometry.orientedSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer), orientation: orientation)
        stateLock.lock(); status.rgb = rgb; status.imageWidth = w; status.imageHeight = h
        status.sampledFrames &+= 1; status.lastVideoAt = Date().timeIntervalSince1970; stateLock.unlock()
    }
    override func broadcastPaused() {
        stateLock.lock(); status.paused = true; stateLock.unlock(); sender.clear()
    }
    override func broadcastResumed() {
        stateLock.lock(); status.paused = false; lastSampleAt = 0; stateLock.unlock()
    }
    override func broadcastFinished() { shutdown() }

    private func maintenance() {
        if let request = SharedStore.read("stop.json", as: StopRequest.self), request.requestedAt > beganAt {
            shutdown(); finishBroadcastWithError(NSError(domain: "ColorLight.Stop", code: 0, userInfo: [NSLocalizedDescriptionKey: "同步已停止"])); return
        }
        let loaded = SharedStore.settings()
        if loaded.isValid {
            stateLock.lock(); let changed = config != loaded; config = loaded; stateLock.unlock()
            if changed { sender.configure(loaded, keepStaticColor: true); sender.clear() }
        }
        let sent = sender.snapshot
        stateLock.lock()
        guard !ending else { stateLock.unlock(); return }
        status.updatedAt = Date().timeIntervalSince1970; status.submitted = sent.submitted
        status.message = status.paused ? "系统已暂停采集" : status.lastVideoAt == 0 ? "等待首帧" : status.updatedAt-status.lastVideoAt > 3 ? "暂未收到新画面" : sent.message
        let report = status; stateLock.unlock()
        try? SharedStore.write(report, name: "status.json")
    }
    private func shutdown() {
        stateLock.lock()
        guard !ending else { stateLock.unlock(); return }
        ending = true; status.active = false; status.updatedAt = Date().timeIntervalSince1970; status.message = "已停止"
        let report = status; stateLock.unlock()
        ticker?.cancel(); ticker = nil; sender.stop(); try? SharedStore.write(report, name: "status.json")
    }
    private func fail(_ text: String) {
        finishBroadcastWithError(NSError(domain: "ColorLight", code: 1, userInfo: [NSLocalizedDescriptionKey: text]))
    }
}
