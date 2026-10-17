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
    private var pacer = FramePacer()
    private var ending = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard SharedStore.root != nil else { fail("共享容器不可用：\(SharedStore.groupID)。请核对两个目标的 App Groups 签名"); return }
        let loaded = SharedStore.settings()
        guard loaded.isValid else { fail("请先在取色点灯 App 中保存有效设置"); return }
        stateLock.lock(); config = loaded; beganAt = Date().timeIntervalSince1970
        status = BroadcastStatus(); status.active = true; status.message = "等待屏幕画面"; ending = false; pacer.reset(); stateLock.unlock()
        sender.configure(loaded, keepStaticColor: true)
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(400), leeway: .milliseconds(30))
        source.setEventHandler { [weak self] in self?.maintenance() }
        ticker = source; source.resume()
    }
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let capturedAt = ProcessInfo.processInfo.systemUptime
        stateLock.lock()
        let c = config, paused = status.paused || ending
        let due = !paused && pacer.accepts(at: capturedAt, fps: c.fps)
        stateLock.unlock()
        guard !paused, due, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let attached = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber
        let orientation = attached?.uint32Value ?? 1
        guard let rgb = PixelSampler.sample(buffer, settings: c, orientation: orientation) else {
            stateLock.lock(); status.message = "当前画面格式暂不支持"; stateLock.unlock(); return
        }
        let sampleMS = (ProcessInfo.processInfo.systemUptime - capturedAt) * 1000
        sender.offer(rgb, brightness: c.brightness, capturedAt: capturedAt, samplingMS: sampleMS)
        let (w,h) = SampleGeometry.orientedSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer), orientation: orientation)
        stateLock.lock(); status.rgb = rgb; status.imageWidth = w; status.imageHeight = h
        status.sampledFrames &+= 1; status.lastVideoAt = Date().timeIntervalSince1970; stateLock.unlock()
    }
    override func broadcastPaused() {
        stateLock.lock(); status.paused = true; stateLock.unlock(); sender.clear()
    }
    override func broadcastResumed() {
        stateLock.lock(); status.paused = false; pacer.reset(); stateLock.unlock()
    }
    override func broadcastFinished() { shutdown() }

    private func maintenance() {
        if let request = SharedStore.read("stop.json", as: StopRequest.self), request.requestedAt > beganAt {
            shutdown(); finishBroadcastWithError(NSError(domain: "ColorLight.Stop", code: 0, userInfo: [NSLocalizedDescriptionKey: "同步已停止"])); return
        }
        let loaded = SharedStore.settings()
        if loaded.isValid {
            stateLock.lock(); let changed = config != loaded; config = loaded
            let lastColor = status.rgb, hasFrame = status.sampledFrames > 0, paused = status.paused
            stateLock.unlock()
            if changed {
                sender.clear(); sender.configure(loaded, keepStaticColor: true)
                // Brightness/transport edits must also take effect on an idle,
                // unchanged screen without waiting for ReplayKit to emit again.
                if hasFrame && !paused { sender.offer(lastColor, brightness: loaded.brightness) }
            }
        }
        let sent = sender.snapshot
        stateLock.lock()
        guard !ending else { stateLock.unlock(); return }
        status.updatedAt = Date().timeIntervalSince1970; status.submitted = sent.submitted; status.timing = sent.timing
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
