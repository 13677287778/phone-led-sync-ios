import Foundation
import Network
import CoreBluetooth

struct BLEChoice: Identifiable, Equatable {
    var id: String
    var name: String
    var rssi: Int
}
struct SenderSnapshot {
    var ready = false
    var message = "未连接"
    var submitted: UInt64 = 0
    var devices: [BLEChoice] = []
}

/// This sender lives INSIDE the upload extension while broadcasting, not in the
/// suspended containing app. Wi-Fi/BLE use the exact same 16-byte firmware frame.
final class ColorSender: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let service = CBUUID(string: "2e8a0001-7d8b-4c27-9f4e-74c62f671001")
    static let write = CBUUID(string: "2e8a0002-7d8b-4c27-9f4e-74c62f671001")
    let mailbox = LatestColorMailbox()
    private let queue = DispatchQueue(label: "ColorLight.latestSender", qos: .userInteractive)
    private let lock = NSLock()
    private var report = SenderSnapshot()
    private var timer: DispatchSourceTimer?
    private var settings = LEDSettings()
    private var key = ""
    private var generation = 0
    private var enabled = false
    private var scanningOnly = false
    private var udp: NWConnection?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var found: [String: BLEChoice] = [:]
    private var ready = false
    private var inFlight = false
    private var retryScheduled = false
    private var session = UInt32.random(in: 1...UInt32.max)
    private var sequence: UInt32 = 0
    private var lastSent: LEDFrame?
    private var lastSentAt = 0.0
    private var keepStaticColor = false
    // Broadcaster stops refreshing a color when no screen frames arrive.
    var snapshot: SenderSnapshot { lock.lock(); defer { lock.unlock() }; return report }

    override init() {
        super.init()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source; source.resume()
    }
    deinit { timer?.cancel(); udp?.cancel() }

    func configure(_ config: LEDSettings, scanOnly: Bool = false, keepStaticColor: Bool = false) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let nextKey = "\(config.mode.rawValue)|\(config.host)|\(config.port)|\(config.peripheralID)|\(scanOnly)"
            self.settings = config
            self.keepStaticColor = keepStaticColor
            if self.enabled && self.key == nextKey { return }
            self.disconnect()
            self.generation += 1; self.enabled = true; self.key = nextKey; self.scanningOnly = scanOnly
            self.session = UInt32.random(in: 1...UInt32.max); self.sequence = 0; self.lastSent = nil
            if config.mode == .wifi {
                guard config.isValid else { self.publish("连接参数无效"); return }
                self.connectWiFi()
            } else {
                if self.central == nil { self.central = CBCentralManager(delegate: self, queue: self.queue) }
                else { self.ensureBLE() }
            }
        }
    }
    func offer(_ rgb: RGB, brightness: Int) {
        mailbox.offer(LEDFrame(rgb: rgb, brightness: UInt8(clamping: brightness)))
    }
    func clear() { mailbox.clear() }
    func stop() {
        mailbox.clear()
        queue.async { [weak self] in
            guard let self = self else { return }
            self.enabled = false; self.generation += 1; self.key = ""; self.disconnect(); self.publish("未连接")
        }
    }
    private func disconnect() {
        ready = false; inFlight = false; retryScheduled = false; characteristic = nil
        udp?.stateUpdateHandler = nil; udp?.cancel(); udp = nil
        central?.stopScan()
        if let p = peripheral { p.delegate = nil; central?.cancelPeripheralConnection(p) }
        peripheral = nil
    }
    private func publish(_ message: String) {
        lock.lock(); report.ready = ready; report.message = message
        report.devices = found.values.sorted { $0.rssi > $1.rssi }; lock.unlock()
    }
    private func connected(_ message: String) {
        ready = true; session = UInt32.random(in: 1...UInt32.max); sequence = 0; lastSent = nil; lastSentAt = 0
        publish(message)
    }
    private func connectWiFi() {
        guard enabled, settings.mode == .wifi, let port = NWEndpoint.Port(rawValue: UInt16(settings.port)) else { return }
        ready = false; inFlight = false; publish("等待 Wi-Fi / 本地网络权限")
        let params = NWParameters.udp
        params.requiredInterfaceType = .wifi
        let conn = NWConnection(host: NWEndpoint.Host(settings.host), port: port, using: params)
        udp = conn
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self = self, let conn = conn, self.udp === conn else { return }
            switch state {
            case .ready: self.connected("Wi-Fi 可发送 · UDP 无回执")
            case .waiting(let error): self.ready = false; self.publish("等待网络：\(error.localizedDescription)")
            case .failed(let error):
                self.ready = false; self.publish("网络异常：\(error.localizedDescription)")
                self.retryWiFi()
            case .cancelled: self.ready = false
            default: break
            }
        }
        conn.start(queue: queue)
    }
    private func retryWiFi() {
        guard !retryScheduled else { return }
        retryScheduled = true
        let expected = generation
        queue.asyncAfter(deadline: .now()+1) { [weak self] in
            guard let self = self, self.enabled, self.generation == expected, self.settings.mode == .wifi else { return }
            self.retryScheduled = false
            self.udp?.stateUpdateHandler = nil; self.udp?.cancel(); self.connectWiFi()
        }
    }
    private func tick() {
        guard enabled, !scanningOnly, ready, !inFlight, let entry = mailbox.read() else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard keepStaticColor || now-entry.timestamp < 3 else { return }
        guard entry.frame != lastSent || now-lastSentAt >= 0.75 else { return }
        let next = sequence &+ 1
        let data = entry.frame.encode(session: session, sequence: next)
        if settings.mode == .wifi {
            guard let conn = udp else { return }
            inFlight = true
            let expected = generation
            conn.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self = self, self.generation == expected else { return }
                self.inFlight = false
                if error == nil { self.didSubmit(entry.frame, sequence: next, at: now) }
                else { self.ready = false; self.publish("发送失败，正在重连"); self.retryWiFi() }
            })
        } else {
            guard let p = peripheral, let c = characteristic, p.state == .connected,
                  p.canSendWriteWithoutResponse, p.maximumWriteValueLength(for: .withoutResponse) >= data.count else { return }
            p.writeValue(data, for: c, type: .withoutResponse)
            didSubmit(entry.frame, sequence: next, at: now)
        }
    }
    private func didSubmit(_ frame: LEDFrame, sequence next: UInt32, at now: Double) {
        sequence = next; lastSent = frame; lastSentAt = now
        lock.lock(); report.submitted &+= 1; lock.unlock()
    }
    func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        guard enabled, settings.mode == .ble else { return }
        if manager.state != .poweredOn {
            peripheral?.delegate = nil; peripheral = nil; characteristic = nil; ready = false
        }
        ensureBLE()
    }
    private func ensureBLE() {
        guard enabled, settings.mode == .ble, let manager = central else { return }
        guard manager.state == .poweredOn else {
            ready = false
            publish(manager.state == .unauthorized ? "请允许蓝牙权限" : manager.state == .poweredOff ? "请开启蓝牙" : "蓝牙未就绪")
            return
        }
        if !scanningOnly, let id = UUID(uuidString: settings.peripheralID),
           let p = manager.retrievePeripherals(withIdentifiers: [id]).first {
            connect(p); return
        }
        publish(scanningOnly ? "扫描 ColorLight…" : "寻找已选灯板…")
        manager.scanForPeripherals(withServices: [Self.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    func centralManager(_ manager: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard enabled, settings.mode == .ble else { return }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? "ColorLight"
        let id = p.identifier.uuidString
        found[id] = BLEChoice(id: id, name: name, rssi: RSSI.intValue); publish(scanningOnly ? "选择灯板" : "寻找已选灯板…")
        if !scanningOnly && settings.peripheralID == id { connect(p) }
    }
    private func connect(_ p: CBPeripheral) {
        guard peripheral == nil else { return }
        central?.stopScan(); peripheral = p; p.delegate = self; publish("连接灯板…")
        central?.connect(p, options: nil)
        let expected = generation
        queue.asyncAfter(deadline: .now()+10) { [weak self, weak p] in
            guard let self = self, let p = p, self.generation == expected, self.peripheral === p, !self.ready else { return }
            self.central?.cancelPeripheralConnection(p)
        }
    }
    func centralManager(_ manager: CBCentralManager, didConnect p: CBPeripheral) {
        guard peripheral === p else { manager.cancelPeripheralConnection(p); return }
        p.discoverServices([Self.service])
    }
    func centralManager(_ manager: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { lost(p) }
    func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { lost(p) }
    private func lost(_ p: CBPeripheral) {
        guard peripheral === p else { return }
        p.delegate = nil; peripheral = nil; characteristic = nil; ready = false; publish("蓝牙断开，正在重连")
        let expected = generation
        queue.asyncAfter(deadline: .now()+1) { [weak self] in
            guard let self = self, self.generation == expected else { return }; self.ensureBLE()
        }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === p else { return }
        guard error == nil, let service = p.services?.first(where: { $0.uuid == Self.service }) else {
            central?.cancelPeripheralConnection(p); return
        }
        p.discoverCharacteristics([Self.write], for: service)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === p else { return }
        guard error == nil, let c = service.characteristics?.first(where: { $0.uuid == Self.write }),
              c.properties.contains(.writeWithoutResponse), p.maximumWriteValueLength(for: .withoutResponse) >= 16 else {
            publish("灯板特征不兼容"); central?.cancelPeripheralConnection(p); return
        }
        characteristic = c; connected("BLE 已连接 · 写入无回执")
    }
    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) { if peripheral === p { tick() } }
}
