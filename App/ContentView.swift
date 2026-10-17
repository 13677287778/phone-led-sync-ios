import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var advanced = false
    @State private var showPhotos = false
    @State private var showPoint = false
    @State private var pointU = 0.5
    @State private var pointV = 0.5
    private let accent = Color(red: 0, green: 0.5, blue: 0.46)
    private let ink = Color(red: 0.08, green: 0.18, blue: 0.21)

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
        .onChange(of: model.xPercent) { _ in model.saveQuietly() }
        .onChange(of: model.yPercent) { _ in model.saveQuietly() }
        .onChange(of: model.settings.mode) { _ in model.endManual(); model.saveQuietly() }
        .onChange(of: model.settings.area) { _ in model.saveQuietly() }
        .onChange(of: model.settings.fps) { _ in model.saveQuietly() }
        .onChange(of: model.hostText) { _ in model.saveQuietly() }
        .onChange(of: model.portText) { _ in model.saveQuietly() }
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
                }
                Spacer(minLength: 8)
                Circle().fill(Color(red: Double(model.currentColor.r)/255,green: Double(model.currentColor.g)/255,blue: Double(model.currentColor.b)/255))
                    .frame(width: 64,height: 64).overlay(Circle().stroke(Color.white.opacity(0.2),lineWidth: 1))
            }
            if model.isBroadcasting {
                Button("停止同步",action: model.stopBroadcast).fontWeight(.semibold)
                    .frame(maxWidth: .infinity).padding(.vertical,15).background(Color.red.opacity(0.8)).cornerRadius(12)
            } else if model.pickerReady && !model.preparing {
                HStack {
                    Text("开始同步").fontWeight(.semibold)
                    Spacer()
                    SystemBroadcastButton().frame(width: 52,height: 52)
                }.padding(.leading,18).padding(.trailing,6).background(accent).cornerRadius(12)
            } else {
                Button(action: model.prepareBroadcast) {
                    HStack {
                        if model.preparing { ProgressView().tint(.white) }
                        Text(model.preparing ? "连接中…" : "开始同步").fontWeight(.semibold)
                    }.frame(maxWidth: .infinity).padding(.vertical,15)
                }.buttonStyle(.plain).background(accent).cornerRadius(12).disabled(model.preparing)
            }
        }
        .padding(20).foregroundColor(.white).background(ink).cornerRadius(20)
    }
    private var connectionPanel: some View {
        VStack(alignment: .leading,spacing: 12) {
            HStack { Text("连接").fontWeight(.semibold); Spacer() }
            Picker("连接方式", selection: $model.settings.mode) {
                Text("Wi-Fi").tag(LinkMode.wifi); Text("蓝牙 BLE").tag(LinkMode.ble)
            }.pickerStyle(.segmented).disabled(model.isBroadcasting || model.preparing)
            if model.settings.mode == .wifi {
                HStack { Text("\(model.hostText) · \(model.portText)").font(.caption.monospaced()); Spacer()
                    Button("连接说明") { model.error = "连接 Wi-Fi 123456，密码 12345678，并保持连接。首次请点灯光测试并允许本地网络访问。" }.font(.caption)
                }
            } else {
                HStack { Text(model.settings.peripheralName.isEmpty ? "未选择灯板" : model.settings.peripheralName).font(.caption); Spacer()
                    Button(model.scanning ? "扫描中…" : "扫描",action: model.scan).font(.caption).disabled(model.scanning || model.isBroadcasting)
                }
                if model.scanning || (model.settings.peripheralID.isEmpty && !model.senderState.devices.isEmpty) {
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
                timingPanel
                Text("共享组：\(SharedStore.groupID)").font(.caption2).foregroundColor(.secondary).frame(maxWidth: .infinity,alignment: .leading)
            }.padding(.top,14)
        }.font(.subheadline).padding(16).background(Color.white).cornerRadius(18)
    }
    private var timingPanel: some View {
        VStack(alignment: .leading,spacing: 7) {
            Text("App 内部耗时").font(.caption.weight(.semibold))
            if let t = model.broadcast.timing {
                Text(String(format: "取色均值  %.2f ms",t.averageSampleMS))
                Text(String(format: "回调到提交  均值 %.2f / P95 %.2f ms",t.averageSubmitMS,t.p95SubmitMS))
                Text("最近 \(t.count) 个颜色更新帧")
            } else { Text("同步并变换画面后显示") }
            Text("不含系统采集、无线传输和灯板发光时间")
        }.font(.caption2).foregroundColor(.secondary).frame(maxWidth: .infinity,alignment: .leading)
    }
    private func testButton(_ text: String,_ rgb: RGB,_ tint: Color) -> some View {
        Button(text) { model.test(rgb) }.font(.subheadline).foregroundColor(tint).frame(maxWidth: .infinity).padding(.vertical,10).background(tint.opacity(0.08)).cornerRadius(9)
    }
    private var pointSheet: some View {
        NavigationView {
            VStack(spacing: 12) {
                if let image = model.screenshot { ScreenshotPointView(image: image,u: $pointU,v: $pointV) }
                Text(String(format: "X %.2f%%   Y %.2f%%",pointU*100,pointV*100)).font(.caption.monospaced())
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
}
