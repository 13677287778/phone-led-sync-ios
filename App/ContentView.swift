import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var advanced = false
    @State private var showPhotos = false
    @State private var showPoint = false
    @State private var showStart = false
    @State private var pointU = 0.5
    @State private var pointV = 0.5
    private let accent = Color(red: 0, green: 0.5, blue: 0.46)
    private let ink = Color(red: 0.08, green: 0.18, blue: 0.21)
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("取色点灯").font(.system(size: 28,weight: .bold))
                    Spacer()
                    Label(model.isBroadcasting ? "同步中" : "待机",systemImage: "circle.fill")
                        .font(.caption).foregroundColor(model.isBroadcasting ? accent : .secondary)
                }.padding(.top,8)
                colorPanel
                connectionPanel
                samplingPanel
                advancedPanel
            }
            .frame(maxWidth: 620).padding(20).frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.96,green: 0.97,blue: 0.98).ignoresSafeArea())
        .foregroundColor(ink).tint(accent)
        .sheet(isPresented: $showPhotos) {
            ScreenshotPicker { image in
                showPhotos = false
                if let image = image {
                    model.screenshot = image; pointU = model.settings.u; pointV = model.settings.v
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.4) { showPoint = true }
                }
            }
        }
        .sheet(isPresented: $showPoint) { pointSheet }
        .sheet(isPresented: $showStart) { startSheet }
        .alert("提示", isPresented: Binding(get: { model.error != nil },set: { if !$0 { model.error = nil } })) {
            Button("知道了",role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private var colorPanel: some View {
        VStack(alignment: .leading,spacing: 14) {
            HStack {
                VStack(alignment: .leading,spacing: 9) {
                    Text("当前颜色").font(.caption).foregroundColor(.white.opacity(0.6))
                    Text(model.currentColor.hex).font(.system(size: 32,weight: .semibold,design: .monospaced)).minimumScaleFactor(0.6)
                    Text("R \(model.currentColor.r)   G \(model.currentColor.g)   B \(model.currentColor.b)")
                        .font(.caption.monospaced()).foregroundColor(.white.opacity(0.65))
                }
                Spacer(minLength: 8)
                Circle().fill(Color(red: Double(model.currentColor.r)/255,green: Double(model.currentColor.g)/255,blue: Double(model.currentColor.b)/255))
                    .frame(width: 64,height: 64).overlay(Circle().stroke(Color.white.opacity(0.2),lineWidth: 1))
            }
            Text(model.isBroadcasting ? model.broadcast.message : "固定位置 · 本地取色")
                .font(.caption).foregroundColor(.white.opacity(0.65)).lineLimit(2)
            Button {
                if model.isBroadcasting { model.stopBroadcast() }
                else { model.prepareBroadcast(); if model.error == nil { showStart = true } }
            } label: {
                Text(model.isBroadcasting ? "停止同步" : "开始同步").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical,14)
            }.buttonStyle(.plain).background(model.isBroadcasting ? Color.red.opacity(0.8) : accent).cornerRadius(12)
        }
        .padding(20).foregroundColor(.white).background(ink).cornerRadius(20)
    }
    private var connectionPanel: some View {
        VStack(alignment: .leading,spacing: 12) {
            HStack { Text("连接").fontWeight(.semibold); Spacer(); Text(model.isBroadcasting ? "扩展直连" : model.senderState.ready ? "可发送" : "待连接").font(.caption).foregroundColor(.secondary) }
            Picker("连接方式", selection: $model.settings.mode) {
                Text("Wi-Fi").tag(LinkMode.wifi); Text("蓝牙 BLE").tag(LinkMode.ble)
            }.pickerStyle(.segmented)
            if model.settings.mode == .wifi {
                HStack { Text("\(model.hostText) · \(model.portText)").font(.caption.monospaced()); Spacer()
                    Button("连接说明") { model.error = "连接 Wi-Fi 123456，密码 12345678，并保持连接。首次请点灯光测试并允许本地网络访问。" }.font(.caption)
                }
            } else {
                HStack { Text(model.settings.peripheralName.isEmpty ? "未选择灯板" : model.settings.peripheralName).font(.caption); Spacer()
                    Button(model.scanning ? "扫描中…" : "扫描",action: model.scan).font(.caption).disabled(model.scanning || model.isBroadcasting)
                }
                if model.scanning || !model.senderState.devices.isEmpty {
                    ForEach(model.senderState.devices) { choice in
                        Button { model.choose(choice) } label: {
                            HStack { Text(choice.name); Spacer(); Text("\(choice.rssi) dBm").foregroundColor(.secondary) }.font(.caption)
                        }
                    }
                }
            }
        }.padding(16).background(Color.white).cornerRadius(18)
    }
    private var samplingPanel: some View {
        VStack(alignment: .leading,spacing: 12) {
            HStack { Text("取色位置").fontWeight(.semibold); Spacer()
                Button("截图选点") { model.endManual(); showPhotos = true }.font(.caption)
            }
            HStack(spacing: 14) {
                coordinate("X %",text: $model.xPercent); coordinate("Y %",text: $model.yPercent)
            }
            HStack { Text("亮度").fontWeight(.semibold); Spacer(); Text("\(Int((Double(model.settings.brightness)/255*100).rounded()))%").foregroundColor(accent) }
            Slider(value: Binding(get: { Double(model.settings.brightness) },set: { model.settings.brightness = Int($0) }),in: 0...255,step: 1,onEditingChanged: { editing in if !editing { model.apply() } })
            Button("应用更改",action: model.apply).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(11)
                .background(accent.opacity(0.08)).cornerRadius(10)
        }.padding(16).background(Color.white).cornerRadius(18)
    }
    private func coordinate(_ title: String,text: Binding<String>) -> some View {
        HStack { Text(title).font(.caption).foregroundColor(.secondary)
            TextField("0–100",text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(.subheadline.monospaced())
        }.padding(10).background(Color.gray.opacity(0.06)).cornerRadius(8)
    }
    private var advancedPanel: some View {
        DisclosureGroup("高级设置",isExpanded: $advanced) {
            VStack(spacing: 16) {
                Picker("采样范围",selection: $model.settings.area) { Text("单像素").tag(1); Text("5 × 5 平均色").tag(5) }.pickerStyle(.segmented)
                Picker("采样上限",selection: $model.settings.fps) { Text("30 Hz").tag(30); Text("60 Hz").tag(60); Text("120 Hz").tag(120) }.pickerStyle(.segmented)
                if model.settings.mode == .wifi {
                    TextField("灯板 IPv4 地址",text: $model.hostText).keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).disableAutocorrection(true)
                    TextField("UDP 端口",text: $model.portText).keyboardType(.numberPad)
                }
                HStack {
                    testButton("红",RGB(r: 255,g: 0,b: 0),.red)
                    testButton("绿",RGB(r: 0,g: 255,b: 0),accent)
                    testButton("蓝",RGB(r: 0,g: 0,b: 255),.blue)
                    testButton("熄灭",.black,.secondary)
                }.disabled(model.isBroadcasting)
                Text(model.isBroadcasting ? "\(model.broadcast.imageWidth) × \(model.broadcast.imageHeight) · 采样 \(model.broadcast.sampledFrames) · 提交 \(model.broadcast.submitted)\n\(model.broadcast.message)" : model.senderState.message)
                    .font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity,alignment: .leading)
                Button("保存设置",action: model.apply)
                Text("提交不代表灯端回执。受保护画面可能取到黑色。").font(.caption2).foregroundColor(.secondary)
            }.padding(.top,14)
        }.font(.subheadline).padding(16).background(Color.white).cornerRadius(18)
    }
    private func testButton(_ text: String,_ rgb: RGB,_ tint: Color) -> some View {
        Button(text) { model.test(rgb) }.font(.subheadline).foregroundColor(tint).frame(maxWidth: .infinity).padding(.vertical,10).background(tint.opacity(0.08)).cornerRadius(9)
    }
    private var pointSheet: some View {
        NavigationView {
            VStack(spacing: 12) {
                if let image = model.screenshot { ScreenshotPointView(image: image,u: $pointU,v: $pointV) }
                Text(String(format: "X %.2f%%   Y %.2f%%",pointU*100,pointV*100)).font(.caption.monospaced())
                Text("使用目标画面的完整截图，不要裁剪。位置相对当前屏幕保存。").font(.caption).foregroundColor(.secondary).padding(.horizontal)
            }.navigationTitle("选择取色位置").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showPoint = false; model.screenshot = nil } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") {
                        model.selectPoint(u: pointU,v: pointV)
                        if model.save() { showPoint = false; model.screenshot = nil }
                    } }
                }
        }.navigationViewStyle(.stack)
    }
    private var startSheet: some View {
        NavigationView {
            VStack(spacing: 22) {
                Image(systemName: "record.circle").font(.system(size: 42)).foregroundColor(accent)
                Text("启动屏幕同步").font(.title2.bold())
                if model.preparing {
                    Text(model.senderState.message).font(.subheadline).multilineTextAlignment(.center)
                    Text("先允许网络或蓝牙访问，再继续。").font(.caption).foregroundColor(.secondary)
                    Button("准备完成，下一步") { model.releaseForBroadcastPicker() }
                        .disabled(!model.senderState.ready)
                } else {
                    HStack {
                        Text("点击右侧系统按钮 → 开始直播").font(.subheadline)
                        SystemBroadcastButton().frame(width: 52,height: 52).background(accent).cornerRadius(12)
                    }
                    Text("“直播”是系统按钮名称。本 App 只在手机本地取色，不上传视频。开始后可切换到其他 App。").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                Text("当前固定位置：X \(model.xPercent)% / Y \(model.yPercent)%").font(.caption.monospaced())
                Spacer(minLength: 0)
            }.padding(24).padding(.top,24).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { showStart = false; model.endManual() } } }
                .onChange(of: model.isBroadcasting) { active in if active { showStart = false } }
        }.navigationViewStyle(.stack)
    }
}
