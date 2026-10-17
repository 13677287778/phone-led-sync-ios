#!/usr/bin/env python3
from pathlib import Path
import hashlib
import json
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
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
