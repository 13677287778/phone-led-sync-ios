#!/usr/bin/env python3
from pathlib import Path
import hashlib
import importlib.util
import json
import plistlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
def main():
    subprocess.run([sys.executable,str(ROOT/'Scripts/generate_project.py')],check=True)
    app=plistlib.loads((ROOT/'Config/App-Info.plist').read_bytes())
    ext=plistlib.loads((ROOT/'Config/Broadcast-Info.plist').read_bytes())
    ent=plistlib.loads((ROOT/'Config/Shared.entitlements').read_bytes())
    assert app['ColorLightAppGroup']==ext['ColorLightAppGroup']==ent['com.apple.security.application-groups'][0]
    assert 'NSLocalNetworkUsageDescription' in app and 'NSLocalNetworkUsageDescription' not in ext
    assert ext['NSExtension']['NSExtensionPointIdentifier']=='com.apple.broadcast-services-upload'
    assert ext['NSExtension']['NSExtensionAttributes']['RPBroadcastProcessMode']=='RPBroadcastProcessModeSampleBuffer'
    assert not any('private' in k for k in ent)
    pbx=ROOT/'ColorLight.xcodeproj/project.pbxproj';digest=hashlib.sha256(pbx.read_bytes()).digest()
    subprocess.run([sys.executable,str(ROOT/'Scripts/generate_project.py')],check=True)
    assert digest==hashlib.sha256(pbx.read_bytes()).digest(),'Project generator must be deterministic'
    schema=ET.parse(ROOT/'ColorLight.xcodeproj/xcshareddata/xcschemes/ColorLight.xcscheme')
    assert schema.findall('.//TestableReference')
    # Only buildable source families enter targets. The CLI-only test main is not in app/extension.
    spec=importlib.util.spec_from_file_location('generator',ROOT/'Scripts/generate_project.py')
    generator=importlib.util.module_from_spec(spec);spec.loader.exec_module(generator);generator.main()
    refs={v['path'] for v in generator.objects.values() if v['isa']=='PBXFileReference' and v.get('lastKnownFileType')=='sourcecode.swift'}
    for path in refs:assert (ROOT/path).is_file(),path
    for target in ('app','ext'):
        source=generator.objects[generator.uid('sources:'+target)]
        paths=[generator.objects[generator.objects[build]['fileRef']]['path'] for build in source['files']]
        assert 'Tests/main.swift' not in paths and 'Tests/PixelSamplerTests.swift' not in paths
        assert all(p.startswith(('Shared/','App/' if target=='app' else 'Broadcast/')) for p in paths)
    assets=json.loads((ROOT/'Assets.xcassets/AppIcon.appiconset/Contents.json').read_text())
    for icon in assets['images']:assert (ROOT/'Assets.xcassets/AppIcon.appiconset'/icon['filename']).is_file()
    workflow=(ROOT/'.github/workflows/ios.yml').read_text()
    assert 'runs-on: macos-26' in workflow and 'retention-days: 3' in workflow and 'contents: read' in workflow
    print('PASS plist/entitlement/scheme/source-membership/icon/workflow/project determinism checks')

if __name__=='__main__':main()
