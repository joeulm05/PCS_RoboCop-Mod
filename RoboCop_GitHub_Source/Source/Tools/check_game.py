# RoboCop Offline Compatibility Check | Author: Joe "Gambit" Bradford
import ctypes
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parents[2]
if len(sys.argv)!=2:raise SystemExit('Usage: python Source/Tools/check_game.py path/to/PoliceChiefSimulator-Win64-Shipping.exe')
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp);src=p/'probe.c'
    src.write_text('#include "compatibility.h"\n#if defined(_WIN32)\n__declspec(dllexport)\n#endif\nint check(const unsigned char* b,size_t n,char* report){RcpImage im;uint32_t r[4];if(!rcp_open(&im,b,n,0)){snprintf(report,1024,"invalid PE");return 0;}return rcp_resolve(&im,r,report,1024);}\n')
    dll=p/('probe.dll' if sys.platform=='win32' else 'probe.so')
    zig=[shutil.which('zig')] if shutil.which('zig') else [sys.executable,'-m','ziglang']
    subprocess.run(zig+['cc','-shared','-O2','-I',str(root/'Source/Native'),str(src),'-o',str(dll)],check=True)
    library=ctypes.CDLL(str(dll));check=library.check;check.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_void_p]
    data=Path(sys.argv[1]).read_bytes();buffer=ctypes.create_string_buffer(data);report=ctypes.create_string_buffer(1024)
    passed=check(buffer,len(data),report);print(report.value.decode())
    if sys.platform=='win32':
        import _ctypes
        _ctypes.FreeLibrary(library._handle)
    if not passed:raise SystemExit(1)
