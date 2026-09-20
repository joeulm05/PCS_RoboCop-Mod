# RoboCop Native Compatibility Tests | Author: Joe "Gambit" Bradford
import argparse
import ctypes
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PROFILES = json.loads((ROOT/'Source/Native/profiles.json').read_text())

def fixture(shift=0, duplicate=None):
    functions=[]
    cursor=0x1000+shift
    for p in PROFILES:
        functions.append((cursor,p))
        cursor=(cursor+len(bytes.fromhex(p['pattern']))+31)&~15
    if duplicate is not None:
        functions.append((cursor+32,PROFILES[duplicate]))
        cursor+=len(bytes.fromhex(PROFILES[duplicate]['pattern']))+64
    text_size=(cursor-0x1000+511)&~511
    pdata_rva=(0x1000+text_size+4095)&~4095
    entries=[]
    data=bytearray(0x400+text_size+0x1000)
    struct.pack_into('<H',data,0,0x5a4d);struct.pack_into('<I',data,60,0x80)
    struct.pack_into('<IHHIIIHH',data,0x80,0x4550,0x8664,2,12345,0,0,240,0x22)
    op=0x98
    struct.pack_into('<H',data,op,0x20b);struct.pack_into('<I',data,op+56,pdata_rva+0x2000)
    struct.pack_into('<I',data,op+60,0x400);struct.pack_into('<I',data,op+108,16)
    sec=op+240
    struct.pack_into('<8sIIIIIIHHI',data,sec,b'.text',text_size,0x1000,text_size,0x400,0,0,0,0,0x60000020)
    for address,p in functions:
        code=bytes.fromhex(p['pattern']);off=0x400+address-0x1000
        data[off:off+len(code)]=code
        entries.extend((address+a,address+b,pdata_rva+0x800) for a,b in p['segments'])
    po=0x400+text_size
    for i,e in enumerate(entries):struct.pack_into('<III',data,po+12*i,*e)
    struct.pack_into('<II',data,op+136,pdata_rva,len(entries)*12)
    struct.pack_into('<8sIIIIIIHHI',data,sec+40,b'.pdata',0x1000,pdata_rva,0x1000,po,0,0,0,0,0x40000040)
    return data,functions

def mapped(data):
    nt=struct.unpack_from('<I',data,60)[0];op=nt+24
    size=struct.unpack_from('<I',data,op+56)[0];headers=struct.unpack_from('<I',data,op+60)[0];out=bytearray(size);out[:headers]=data[:headers]
    n=struct.unpack_from('<H',data,nt+6)[0];sec=op+struct.unpack_from('<H',data,nt+20)[0]
    for i in range(n):
        va,raw,at=struct.unpack_from('<III',data,sec+i*40+12)
        out[va:va+raw]=data[at:at+raw]
    return out

def compiler():
    return [shutil.which('zig')] if shutil.which('zig') else [sys.executable,'-m','ziglang']

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',type=Path,action='append',default=[]);args=parser.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        p=Path(tmp);src=p/'probe.c'
        src.write_text('#include "compatibility.h"\n#if defined(_WIN32)\n__declspec(dllexport)\n#endif\nint check(const unsigned char* b,size_t n,int mapped,char* report){RcpImage im;uint32_t r[4];if(!rcp_open(&im,b,n,mapped)){snprintf(report,1024,"invalid PE");return 0;}return rcp_resolve(&im,r,report,1024);}\n')
        lib=p/('probe.dll' if sys.platform=='win32' else 'probe.so')
        subprocess.run(compiler()+['cc','-shared','-O2','-I',str(ROOT/'Source/Native'),str(src),'-o',str(lib)],check=True)
        library=ctypes.CDLL(str(lib));check=library.check
        check.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_int,ctypes.c_void_p];check.restype=ctypes.c_int
        total=0
        def verify(b,expected,label,in_memory=False):
            global total
            buffer=ctypes.create_string_buffer(bytes(b));report=ctypes.create_string_buffer(1024)
            got=bool(check(buffer,len(b),in_memory,report));assert got==expected,(label,report.value)
            total+=1;print('PASS:',label,report.value.decode())
        b,f=fixture();verify(b,True,'synthetic PE')
        verify(mapped(b),True,'mapped image',True)
        moved,_=fixture(0x280);verify(moved,True,'all function locations moved')
        for idx,pf in enumerate(PROFILES):
            bad,_=fixture(duplicate=idx);verify(bad,False,'ambiguous '+pf['name'])
            bad,fs=fixture();at=0x400+fs[idx][0]-0x1000
            mask=bytes.fromhex(pf['mask']);position=next(i for i in range(pf['patch_length']+8,len(mask)) if mask[i])
            bad[at+position]^=0x01;verify(bad,False,'body mutation '+pf['name'])
            wild,fs=fixture();at=0x400+fs[idx][0]-0x1000
            for i,m in enumerate(mask):
                if not m:wild[at+i]=(i*37+11)&255
            verify(wild,True,'relocated references '+pf['name'])
        bad,fs=fixture();struct.pack_into('<I',bad,0x188+36,0x40000040);verify(bad,False,'non-executable matches rejected')
        bad,fs=fixture();struct.pack_into('<I',bad,60,0xfffffff0);verify(bad,False,'corrupt PE bounds')
        verify(b[:100],False,'truncated PE')
        bad,fs=fixture();struct.pack_into('<I',bad,0x98+140,1);verify(bad,False,'invalid exception table')
        for game in args.game:
            actual=game.read_bytes();verify(actual,True,'actual '+game.parent.name)
            image=mapped(actual)
            nt=struct.unpack_from('<I',image,60)[0];op=nt+24
            reloc,size=struct.unpack_from('<II',image,op+112+5*8);cursor=reloc
            while cursor<reloc+size:
                page,length=struct.unpack_from('<II',image,cursor)
                assert length>=8 and cursor+length<=reloc+size
                for at in range(cursor+8,cursor+length,2):
                    entry=struct.unpack_from('<H',image,at)[0]
                    if entry>>12==10:
                        target=page+(entry&4095);value=struct.unpack_from('<Q',image,target)[0]
                        struct.pack_into('<Q',image,target,(value+0x100000000)&0xffffffffffffffff)
                cursor+=length
            verify(image,True,'actual ASLR-mapped '+game.parent.name,True)
        print(f'PASS: {total} compatibility checks; same C reader used by installer and runtime')

        if sys.platform=='win32':
            import _ctypes
            _ctypes.FreeLibrary(library._handle)
