#!/usr/bin/env python3
"""Dependency-free, deterministic Xcode project/plists generator."""
from pathlib import Path
import hashlib
import json
import plistlib
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
objects={}
def uid(name):return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def obj(object_name,isa,**fields):
    key=uid(object_name);objects[key]={'isa':isa,**fields};return key
def dump(value,level=0):
    if isinstance(value,dict):
        return '{\n'+''.join('\t'*(level+1)+json.dumps(str(k))+ ' = '+dump(v,level+1)+';\n' for k,v in value.items())+'\t'*level+'}'
    if isinstance(value,list):return '(\n'+''.join('\t'*(level+1)+dump(v,level+1)+',\n' for v in value)+'\t'*level+')'
    return json.dumps(str(value),ensure_ascii=False)
def plist(path,data):
    path=ROOT/path;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(plistlib.dumps(data,sort_keys=False))

def main():
    objects.clear()
    project=uid('project');app=uid('app');ext=uid('ext');tests=uid('tests')
    common=obj('xcconfig','PBXFileReference',lastKnownFileType='text.xcconfig',path='Config/Build.xcconfig',sourceTree='SOURCE_ROOT')
    refs={}
    folders={}
    for folder in ('App','Broadcast','Shared','Tests'):
        children=[]
        for p in sorted((ROOT/folder).glob('*.swift')):
            ref=obj('ref:'+p.name,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=p.relative_to(ROOT).as_posix(),sourceTree='SOURCE_ROOT')
            refs[p.relative_to(ROOT).as_posix()]=ref;children.append(ref)
        folders[folder]=obj('group:'+folder,'PBXGroup',name=folder,children=children,sourceTree='<group>')
    assets=obj('assets','PBXFileReference',lastKnownFileType='folder.assetcatalog',path='Assets.xcassets',sourceTree='SOURCE_ROOT')
    appProduct=obj('app-product','PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='ColorLight.app',sourceTree='BUILT_PRODUCTS_DIR')
    extProduct=obj('ext-product','PBXFileReference',explicitFileType='wrapper.app-extension',includeInIndex=0,path='ColorLightBroadcast.appex',sourceTree='BUILT_PRODUCTS_DIR')
    testProduct=obj('tests-product','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex=0,path='ColorLightTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
    products=obj('products','PBXGroup',name='Products',children=[appProduct,extProduct,testProduct],sourceTree='<group>')
    mainGroup=obj('main-group','PBXGroup',children=[*folders.values(),assets,common,products],sourceTree='<group>')
    def sources(target,paths):
        builds=[obj('build:'+target+':'+p,'PBXBuildFile',fileRef=refs[p]) for p in paths]
        return obj('sources:'+target,'PBXSourcesBuildPhase',buildActionMask=2147483647,files=builds,runOnlyForDeploymentPostprocessing=0)
    def configList(name,base):
        configs=[]
        for mode in ('Debug','Release'):
            settings=dict(base)
            settings.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode=='Debug' else '-O',DEBUG_INFORMATION_FORMAT='dwarf' if mode=='Debug' else 'dwarf-with-dsym')
            if mode=='Debug':settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
            configs.append(obj('config:'+name+mode,'XCBuildConfiguration',baseConfigurationReference=common,buildSettings=settings,name=mode))
        return obj('configs:'+name,'XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
    shared=[p for p in refs if p.startswith('Shared/')]
    appSources=sources('app',shared+[p for p in refs if p.startswith('App/')])
    extSources=sources('ext',shared+['Broadcast/SampleHandler.swift'])
    testSources=sources('tests',['Shared/ColorCore.swift','Shared/PixelSampler.swift','Tests/PixelSamplerTests.swift'])
    assetBuild=obj('asset-build','PBXBuildFile',fileRef=assets)
    resources=obj('app-resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[assetBuild],runOnlyForDeploymentPostprocessing=0)
    extResources=obj('ext-resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
    embedRef=obj('embed-file','PBXBuildFile',fileRef=extProduct,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
    embed=obj('embed','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[embedRef],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0)
    proxy=obj('ext-proxy','PBXContainerItemProxy',containerPortal=project,proxyType=1,remoteGlobalIDString=ext,remoteInfo='ColorLightBroadcast')
    dependency=obj('ext-dependency','PBXTargetDependency',target=ext,targetProxy=proxy)
    projConfig=configList('project',{'SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','TARGETED_DEVICE_FAMILY':'1,2','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','ENABLE_BITCODE':'NO','ALWAYS_SEARCH_USER_PATHS':'NO','SWIFT_EMIT_LOC_STRINGS':'NO'})
    appConfig=configList('app',{'PRODUCT_NAME':'ColorLight','PRODUCT_BUNDLE_IDENTIFIER':'$(COLORLIGHT_BUNDLE_BASE)','INFOPLIST_FILE':'Config/App-Info.plist','CODE_SIGN_ENTITLEMENTS':'Config/Shared.entitlements','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'],'SWIFT_EMIT_LOC_STRINGS':'NO'})
    extConfig=configList('ext',{'PRODUCT_NAME':'ColorLightBroadcast','PRODUCT_BUNDLE_IDENTIFIER':'$(COLORLIGHT_BUNDLE_BASE).Broadcast','INFOPLIST_FILE':'Config/Broadcast-Info.plist','CODE_SIGN_ENTITLEMENTS':'Config/Shared.entitlements','APPLICATION_EXTENSION_API_ONLY':'YES','SKIP_INSTALL':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks','@executable_path/../../Frameworks']})
    testConfig=configList('tests',{'PRODUCT_NAME':'ColorLightTests','PRODUCT_BUNDLE_IDENTIFIER':'$(COLORLIGHT_BUNDLE_BASE).Tests','GENERATE_INFOPLIST_FILE':'YES','CODE_SIGNING_ALLOWED':'NO','SKIP_INSTALL':'YES'})
    obj('app','PBXNativeTarget',buildConfigurationList=appConfig,buildPhases=[appSources,resources,embed],buildRules=[],dependencies=[dependency],name='ColorLight',productName='ColorLight',productReference=appProduct,productType='com.apple.product-type.application')
    obj('ext','PBXNativeTarget',buildConfigurationList=extConfig,buildPhases=[extSources,extResources],buildRules=[],dependencies=[],name='ColorLightBroadcast',productName='ColorLightBroadcast',productReference=extProduct,productType='com.apple.product-type.app-extension')
    obj('tests','PBXNativeTarget',buildConfigurationList=testConfig,buildPhases=[testSources],buildRules=[],dependencies=[],name='ColorLightTests',productName='ColorLightTests',productReference=testProduct,productType='com.apple.product-type.bundle.unit-test')
    obj('project','PBXProject',attributes={'LastUpgradeCheck':'1600','TargetAttributes':{app:{'SystemCapabilities':{'com.apple.ApplicationGroups.iOS':{'enabled':1}}},ext:{'SystemCapabilities':{'com.apple.ApplicationGroups.iOS':{'enabled':1}}}}},buildConfigurationList=projConfig,compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',hasScannedForEncodings=0,knownRegions=['zh-Hans','en','Base'],mainGroup=mainGroup,productRefGroup=products,projectDirPath='',projectRoot='',targets=[app,ext,tests])
    path=ROOT/'ColorLight.xcodeproj';path.mkdir(exist_ok=True)
    (path/'project.pbxproj').write_text('// !$*UTF8*$!\n'+dump({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n',encoding='utf-8')
    commonInfo={'CFBundleDevelopmentRegion':'zh_CN','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','ColorLightAppGroup':'$(COLORLIGHT_APP_GROUP)','NSBluetoothAlwaysUsageDescription':'连接你选择的灯板，并发送本地取到的颜色。'}
    plist('Config/App-Info.plist',{**commonInfo,'CFBundleDisplayName':'取色点灯','CFBundlePackageType':'APPL','LSRequiresIPhoneOS':True,'NSLocalNetworkUsageDescription':'通过 Wi-Fi 直接连接灯板并发送颜色；不上传屏幕画面。','UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'UISupportedInterfaceOrientations~ipad':['UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight']})
    plist('Config/Broadcast-Info.plist',{**commonInfo,'CFBundleDisplayName':'取色点灯','CFBundlePackageType':'XPC!','NSExtension':{'NSExtensionPointIdentifier':'com.apple.broadcast-services-upload','NSExtensionPrincipalClass':'$(PRODUCT_MODULE_NAME).SampleHandler','NSExtensionAttributes':{'RPBroadcastProcessMode':'RPBroadcastProcessModeSampleBuffer'}}})
    plist('Config/Shared.entitlements',{'com.apple.security.application-groups':['$(COLORLIGHT_APP_GROUP)']})
    scheme=ET.Element('Scheme',LastUpgradeVersion='1600',version='1.3')
    build=ET.SubElement(scheme,'BuildAction',parallelizeBuildables='YES',buildImplicitDependencies='YES')
    entries=ET.SubElement(build,'BuildActionEntries')
    def reference(parent,target,name):
        return ET.SubElement(parent,'BuildableReference',BuildableIdentifier='primary',BlueprintIdentifier=target,BuildableName=name,BlueprintName={'ColorLight.app':'ColorLight','ColorLightTests.xctest':'ColorLightTests'}[name],ReferencedContainer='container:ColorLight.xcodeproj')
    entry=ET.SubElement(entries,'BuildActionEntry',buildForTesting='YES',buildForRunning='YES',buildForProfiling='YES',buildForArchiving='YES',buildForAnalyzing='YES');reference(entry,app,'ColorLight.app')
    test=ET.SubElement(scheme,'TestAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',shouldUseLaunchSchemeArgsEnv='YES')
    testables=ET.SubElement(test,'Testables');ref=ET.SubElement(testables,'TestableReference',skipped='NO');reference(ref,tests,'ColorLightTests.xctest')
    launch=ET.SubElement(scheme,'LaunchAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',launchStyle='0',useCustomWorkingDirectory='NO',ignoresPersistentStateOnLaunch='NO',debugDocumentVersioning='YES',allowLocationSimulation='YES')
    reference(ET.SubElement(launch,'BuildableProductRunnable',runnableDebuggingMode='0'),app,'ColorLight.app')
    ET.SubElement(scheme,'AnalyzeAction',buildConfiguration='Debug');ET.SubElement(scheme,'ArchiveAction',buildConfiguration='Release',revealArchiveInOrganizer='YES')
    schemes=path/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
    ET.indent(scheme);ET.ElementTree(scheme).write(schemes/'ColorLight.xcscheme',encoding='utf-8',xml_declaration=True)
    workspace=path/'project.xcworkspace';workspace.mkdir(exist_ok=True)
    (workspace/'contents.xcworkspacedata').write_text('<?xml version="1.0"?><Workspace version="1.0"><FileRef location="self:"/></Workspace>\n',encoding='utf-8')
    print('Generated deterministic ColorLight.xcodeproj (app + upload extension + simulator tests)')

if __name__=='__main__':main()
