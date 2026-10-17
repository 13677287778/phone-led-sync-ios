from pathlib import Path
import json,struct,zlib,math
r=Path(__file__).resolve().parents[1];d=r/'Assets.xcassets';d.mkdir(exist_ok=True)
(d/'Contents.json').write_text(json.dumps({'info':{'version':1,'author':'xcode'}}),encoding='utf-8')
a=d/'AppIcon.appiconset';a.mkdir(exist_ok=True)
images=[]
for idiom,points,scales in [('iphone',20,[2,3]),('iphone',29,[2,3]),('iphone',40,[2,3]),('iphone',60,[2,3]),('ipad',20,[1,2]),('ipad',29,[1,2]),('ipad',40,[1,2]),('ipad',76,[1,2]),('ipad',83.5,[2]),('ios-marketing',1024,[1])]:
    for scale in scales:
        n=int(points*scale);name=f'icon-{n}.png'
        images.append({'idiom':idiom,'size':f'{points}x{points}','scale':f'{scale}x','filename':name})
        if (a/name).exists():continue
        rows=bytearray()
        for y in range(n):
            rows.append(0)
            for x in range(n):
                u=(x+.5)/n-.5;v=(y+.5)/n-.5;dist=math.hypot(u,v)
                color=(20,45,53)
                if dist<.285:color=(0,160,145)
                if .295<dist<.314:color=(128,220,205)
                if abs(u)<.011 and .35<abs(v)<.41 or abs(v)<.011 and .35<abs(u)<.41:color=(240,252,250)
                if dist<.055:color=(239,255,251)
                rows+=bytes(color)
        def chunk(kind,b):return struct.pack('>I',len(b))+kind+b+struct.pack('>I',zlib.crc32(kind+b)&0xffffffff)
        png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',n,n,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(rows,8))+chunk(b'IEND',b'')
        (a/name).write_bytes(png)
(a/'Contents.json').write_text(json.dumps({'images':images,'info':{'version':1,'author':'xcode'}},indent=2),encoding='utf-8')
print('Native app icon assets generated')
