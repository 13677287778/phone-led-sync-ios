# 取色点灯 · iOS

普通、未越狱 iPhone/iPad：屏幕指定位置取色 → Wi-Fi UDP / BLE → 同一块 ESP32-C3-Zero 灯板。

**设计最低版本 iOS/iPadOS 15.0，不写死机型或分辨率。编译/测试结果以 Actions 记录为准；尚未声称通过真实 iPhone 的屏幕采集、BLE 或光学延迟测试。**

## 使用

1. 给灯板供电。Wi-Fi 名称 `123456`，密码 `12345678`，默认灯板 `192.168.4.1:45679`。
2. 用主 App 的“高级设置 → 红/绿/蓝”先测试灯光，并允许“本地网络”访问。BLE 模式先扫描、选择灯板和授权。
3. “截图选点”导入目标画面的**完整未裁剪截图**，点击/拖动标记后保存；或直接填 X/Y 百分比。
4. 在首页“开始同步”一行点击系统广播按钮并确认。首次需要连接/授权时会先进行准备，准备完成自动释放主 App 连接，不再显示额外说明页或“下一步”。已授权的 BLE 可直接进入系统确认。
5. 切换到目标 App。取样和发送由**广播扩展自己执行**，不依赖主 App 继续在后台跑定时器。
6. 位置、亮度、采样设置自动保存有效值；连接方式在同步时锁定，停止后切换。停止可用首页按钮或系统录屏入口。

选点相对**当前方向的可见画面**，横竖屏按比例采样；不同方向/UI 布局并不保证同一业务元素位置，应各自选点。支持单像素/5×5、30/60/120 Hz 采样上限，实际频率受 ReplayKit 和显示更新限制。

普通 iOS 没有本项目可用的安卓式跨应用浮窗。受保护视频可能黑屏，锁屏/系统暂停以 ReplayKit 生命周期为准。USB/Lightning CDC 不在此版范围内。BLE 是同协议实现，仍需真实设备验证。

## 构建

无需 CocoaPods、XcodeGen 或第三方 iOS SDK。工程已生成，直接打开 `ColorLight.xcodeproj`。

macOS + Xcode：

```sh
bash Scripts/build_unsigned.sh
bash Scripts/test_simulator.sh
```

GitHub Actions 使用标准 `macos-26`、只读仓库权限、并发取消旧任务和 40 分钟上限。公开仓库标准机器的运行时间按 GitHub 规则免费；产物只保留3天，不启用大型付费机器。

成功后下载 `ColorLight-iOS-*` 产物中的 `ColorLight-1.0.2-unsigned.ipa`。它是 **arm64 真机包，不是模拟器 App**，尚未签名，不能直接在正常 iPhone 上运行。

## 签名必须匹配

本项目不包含证书、私钥或描述文件；不使用巨魔/私有权限。

- 主 App：`com.colorlight.ledsync`
- 广播扩展：`com.colorlight.ledsync.Broadcast`
- App Group：`group.com.colorlight.ledsync`

手动运行 Actions 时，可通过 `app_group` 参数填写实际描述文件共同授权的组；该参数同时进入主 App、广播扩展的 Info.plist 和签名权限模板。打包器会核对最终两边值，防止只改一处。默认不填仍使用上述配置。此参数仅选择已有授权组，不会新增苹果授权；不要填写证书或密码。主界面高级设置可查看本次包实际使用的共享组。

如果你的账号不能使用这些标识符，在 `Config/Build.xcconfig` 同时更改 Bundle Base 与已注册的 App Group，再重新编译。**先定最终标识符再签名，不要只改外层包名**。

主 App 与 `.appex` 都须由同一团队签名，均带有相同且已注册的 App Groups 权限、相应描述文件；签名工具若剥离这些权限，App 能打开也可能无法读取共享设置或启动广播。不能把任意普通签名服务视为已满足这一条件。

本地网络授权在主 App 前台触发；扩展共享授权状态。BLE 的主 App 连接先释放，再交给扩展，不同时占用灯板。

## 数据与协议

- 没有账号、广告、云服务或音视频上传。音频帧被忽略。
- 导入截图只在主 App 内存中用于选点，不传到扩展、灯板或网络。
- App Group 内只有配置、低频 RGB/运行状态和停止命令；不写整帧图像。
- 共用安卓/固件的16字节 `CL` v1协议、随机会话、递增序号、XOR、原 UUID 和 UDP45679，无需重刷开发板。
- 取最新颜色、最多一个待发送颜色/一个 UDP 在途发送，BLE用 `canSendWriteWithoutResponse` 背压；不堆积旧帧。
- 静态颜色约0.75秒心跳。暂停/停止后停止心跳，灯端约2秒熄灭。进程退出依靠灯端超时。
- UDP/BLE无响应写入的“提交”不是接收确认，更不是屏幕到发光总延迟。

### 1.0.2：延迟链路与界面

- 新颜色经 `DispatchSourceUserDataAdd` 合并唤醒，取消每帧等待8ms轮询；UDP在途完成和BLE可写回调直接处理最新槽。低频计时器仅负责静态心跳/恢复。
- 相位采样器容忍小幅回调抖动，避免“上次回调起重新计满一周期”导致额外漏采。模拟回调回归不代表真实设备帧率。
- 暂停与结束前重新核对状态，防止正在采样的帧在清空颜色后又恢复心跳。
- 高级设置显示最近120个颜色更新帧的取色耗时、回调到发送API调用的均值/P95；手动灯光测试和静态重复心跳不当作新帧计入。此值不包括回调之前的系统采集、无线与灯端时间，也不代表端到端延迟。
- 删除额外启动说明页与“下一步”；已授权BLE可直接点击首页系统广播按钮。首次Wi-Fi/未授权BLE仍在前台完成授权准备，自动释放主App连接后显示系统按钮；不绕过系统确认。
- 取色坐标、亮度、采样参数自动保存有效值，移除重复“应用更改/保存设置”按钮。共享组、协议、截图选点方式保持不变。

## 验证

- `Tests/main.swift`：真实 Swift 编码黄金向量、整数端序、8种方向、边界/不同分辨率、YUV和并发最新值槽。
- `Tests/PixelSamplerTests.swift`：模拟器 CoreVideo BGRA行跨度、5×5边缘平均、旋转和NV12采样。
- `Scripts/package_ipa.py`：真机平台、内嵌扩展、包标识和共享组一致性、IPA结构校验。
- 需后续实机验证：SE3/iOS27授权与连续跨App取色、实际帧格式/颜色、BLE、旋转、停止及延迟。模拟器通过不等于这些通过。

官方资料：[ReplayKit](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler)、[本地网络与扩展权限](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)、[App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)、[BLE 背压](https://developer.apple.com/documentation/corebluetooth/cbperipheral/cansendwritewithoutresponse)。
