# RoboCop Compatibility Check | Author: Joe "Gambit" Bradford
function Assert-RcpCompatibility([string]$Package, $Game) {
    if (-not [Environment]::Is64BitProcess) { throw 'Run the installer with 64-bit Windows PowerShell.' }
    if (-not ('RcpCompatibilityNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class RcpCompatibilityNative {
    [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr LoadLibraryExW(string name, IntPtr file, uint flags);
    [DllImport("kernel32", CharSet=CharSet.Ansi, ExactSpelling=true)]
    static extern IntPtr GetProcAddress(IntPtr module, string name);
    [DllImport("kernel32")]
    static extern bool FreeLibrary(IntPtr module);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl, CharSet=CharSet.Unicode)]
    delegate int Probe([MarshalAs(UnmanagedType.LPWStr)] string path, IntPtr report, uint capacity);
    public static string Check(string dll, string exe) {
        IntPtr module=LoadLibraryExW(dll, IntPtr.Zero, 0x1000);
        if(module==IntPtr.Zero) throw new InvalidOperationException("Cannot load the verified compatibility checker: Win32 error " + Marshal.GetLastWin32Error());
        IntPtr buffer=IntPtr.Zero;
        try {
            IntPtr address=GetProcAddress(module, "robocop_check_file");
            if(address==IntPtr.Zero) throw new InvalidOperationException("Compatibility checker export is missing.");
            Probe probe=(Probe)Marshal.GetDelegateForFunctionPointer(address, typeof(Probe));
            buffer=Marshal.AllocHGlobal(1024);
            Marshal.WriteByte(buffer, 0);
            int result=probe(exe,buffer,1024);
            string report=Marshal.PtrToStringAnsi(buffer);
            if(result!=1) throw new InvalidOperationException("RoboCop cannot verify patrol protection: " + report + ". No game files changed.");
            return report;
        } finally { if(buffer!=IntPtr.Zero) Marshal.FreeHGlobal(buffer); FreeLibrary(module); }
    }
}
'@
    }
    $dll = Join-RcpPath $Package 'Payload/RoboCopGameplay/robocop_native.dll'
    $report = [RcpCompatibilityNative]::Check($dll, $Game.Exe)
    Write-Host "Gameplay compatibility: $report"
}
