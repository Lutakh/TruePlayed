import struct,sys,glob,os
def cmap(path):
    b=open(path,'rb').read()
    n=struct.unpack('>H',b[4:6])[0]; tabs={}
    for i in range(n):
        tag,cs,off,ln=struct.unpack('>4sIII',b[12+16*i:28+16*i]); tabs[tag]=(off,ln)
    off=tabs[b'cmap'][0]; nt=struct.unpack('>H',b[off+2:off+4])[0]; cps=set(); best=None
    for i in range(nt):
        pid,eid,so=struct.unpack('>HHI',b[off+4+8*i:off+12+8*i]); st=off+so; fmt=struct.unpack('>H',b[st:st+2])[0]
        if fmt==4:
            seg=struct.unpack('>H',b[st+6:st+8])[0]//2
            ends=struct.unpack('>%dH'%seg,b[st+14:st+14+2*seg]); s0=st+16+2*seg
            starts=struct.unpack('>%dH'%seg,b[s0:s0+2*seg]); d0=s0+2*seg
            deltas=struct.unpack('>%dh'%seg,b[d0:d0+2*seg]); r0=d0+2*seg
            ros=struct.unpack('>%dH'%seg,b[r0:r0+2*seg])
            for k in range(seg):
                for c in range(starts[k],ends[k]+1):
                    if c==0xFFFF: continue
                    if ros[k]==0: g=(c+deltas[k])&0xFFFF
                    else:
                        a=r0+2*k+ros[k]+2*(c-starts[k]); g=struct.unpack('>H',b[a:a+2])[0]
                        if g: g=(g+deltas[k])&0xFFFF
                    if g: cps.add(c)
        elif fmt==12:
            ng=struct.unpack('>I',b[st+12:st+16])[0]
            for k in range(ng):
                s,e,g=struct.unpack('>III',b[st+16+12*k:st+28+12*k])
                for c in range(s,e+1): cps.add(c)
    return b[:4],cps

# Reference for tests/check_media.lua (same union of format 4 and 12 subtables).
# Usage: python3 tools/ttf_cmap.py Media/Fonts/*.ttf
if __name__ == '__main__':
    BODY = set(range(0x20, 0x7F)) | {0xA0, 0xAB, 0xB7, 0xBB} | (set(range(0xC0, 0x100)) - {0xD7, 0xF7})
    for path in sys.argv[1:]:
        _, cps = cmap(path)
        cyr = all(c in cps for c in range(0x410, 0x450))
        miss = ' '.join('U+%04X' % c for c in sorted(BODY - cps))
        print(f'{os.path.basename(path)}: {len(cps)} code points, cyr={cyr}, body set missing: {miss or "none"}')
