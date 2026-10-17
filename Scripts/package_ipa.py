#!/usr/bin/env python3
from pathlib import Path
import hashlib
import json
import os
import plistlib
import sys
import zipfile

def main():
    app=Path(sys.argv[1]);out=Path(sys.argv[2])
    info=plistlib.loads((app/'Info.plist').read_bytes())
    ext=app/'PlugIns/ColorLightBroadcast.appex'
    extension=plistlib.loads((ext/'Info.plist').read_bytes())
    assert info['CFBundleSupportedPlatforms']==['iPhoneOS'],'Must be device build, not simulator'
    assert extension['NSExtension']['NSExtensionPointIdentifier']=='com.apple.broadcast-services-upload'
    assert extension['CFBundleIdentifier']==info['CFBundleIdentifier']+'.Broadcast'
    assert info['ColorLightAppGroup']==extension['ColorLightAppGroup']
    assert '$(' not in info['ColorLightAppGroup']
    requested_group=os.environ.get('COLORLIGHT_APP_GROUP')
    if requested_group:
        assert info['ColorLightAppGroup']==requested_group,'App Group build override did not reach both targets'
    binaries=[app/info['CFBundleExecutable'],ext/extension['CFBundleExecutable']]
    for p in binaries:assert p.stat().st_size>4096
    out.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
        for p in sorted(app.rglob('*')):
            if p.is_file():z.write(p,Path('Payload')/app.name/p.relative_to(app))
    sha=hashlib.sha256(out.read_bytes()).hexdigest().upper()
    report={'artifact':out.name,'sha256':sha,'compiled':True,'device_platform':'iPhoneOS','signed':False,'bundle_id':info['CFBundleIdentifier'],'extension_id':extension['CFBundleIdentifier'],'app_group':info['ColorLightAppGroup'],'deployment_target':info.get('MinimumOSVersion'),'iPhone_runtime_verified':False,'screen_capture_verified':False,'optical_latency_measured':False,'note':'Unsigned IPA needs valid signing/profiles for app and broadcast extension including App Groups. Runtime not inferred from compilation.'}
    (out.parent/'build-manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    (out.parent/'SHA256.txt').write_text(f'{sha}  {out.name}\n',encoding='utf-8')
    entitlements={'com.apple.security.application-groups':[info['ColorLightAppGroup']]}
    (out.parent/'app-group.entitlements.plist').write_bytes(plistlib.dumps(entitlements))
    (out.parent/'签名说明.txt').write_text(
        '这是未签名真机IPA，需要你自己的有效证书和匹配的描述文件。\n'
        f"主App：{info['CFBundleIdentifier']}\n广播扩展：{extension['CFBundleIdentifier']}\n共享组：{info['ColorLightAppGroup']}\n"
        '先签内嵌.appex，再签外层.app；两个目标使用同一团队及相同App Group，嵌入各自描述文件。\n'
        'app-group.entitlements.plist只是本项目所需的共享组权限，不是完整签名权限模板，不能代替描述文件。\n'
        '若最终包名要修改，请修改Config/Build.xcconfig并重新编译，不要只重命名外层包。\n'
        '共享组可由 Actions 手动构建的 app_group 参数统一指定，或修改 Config/Build.xcconfig；两边需一致。\n'
        '签名工具去掉共享组权限时，App可能能打开但无法取色同步。\n'
        '编译和模拟器像素测试不等于iPhone屏幕广播、BLE或光学延迟已经实测。\n',encoding='utf-8')
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
