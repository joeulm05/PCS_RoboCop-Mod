/* RoboCop Gameplay v1.0.1 | Author: Joe "Gambit" Bradford */
#include <windows.h>
#include <tlhelp32.h>
#include <psapi.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stddef.h>
#include <wchar.h>
#include "compatibility.h"
#include "build_manifest.h"
typedef struct { uint32_t a,b,c,d; } Guid;
typedef struct { Guid* data; int32_t count,capacity; } GuidArray;
typedef struct { GuidArray officers; unsigned char padding[48]; float success; } Mission;
_Static_assert(offsetof(Mission,success)==0x40,"mission layout");
static Guid targets[64];
static int target_count,installed;
static SRWLOCK lock=SRWLOCK_INIT;
static HMODULE module;
static wchar_t folder[32768];
static char failure[512]="NOT_INITIALIZED";
static LONG warned;
static int matches(const Guid* g){
    if(!g)return 0;int result=0;
    AcquireSRWLockShared(&lock);
    for(int i=0;i<target_count;i++)if(!memcmp(g,&targets[i],sizeof(Guid))){result=1;break;}
    ReleaseSRWLockShared(&lock);return result;
}
static int contains(const GuidArray* a){
    if(!a || !a->data || a->count<1 || a->count>64 || a->capacity<a->count)return 0;
    for(int i=0;i<a->count;i++)if(matches(a->data+i))return 1;
    return 0;
}
#include "gameplay.h"
typedef struct { unsigned char* entry; unsigned char* trampoline; size_t length; unsigned char saved[32],patch[32]; DWORD protection; } Hook;
static Hook hooks[4];
static void status(const char* message){
    if(!folder[0])return;
    wchar_t p[32768];if(_snwprintf(p,32768,L"%ls/native_status.txt",folder)<0)return;
    FILE*f=_wfopen(p,L"wb");if(f){fputs(message,f);fclose(f);}
}
static void fail(const char* message){snprintf(failure,sizeof(failure),"ERROR: %s",message);status(failure);}
static void jump(unsigned char* where,void* to){const unsigned char op[6]={0xff,0x25,0,0,0,0};memcpy(where,op,6);memcpy(where+6,&to,8);}
static int load_targets(void){
    wchar_t p[32768];Guid list[64];int n=0;unsigned int a,b,c,d;
    if(_snwprintf(p,32768,L"%ls/targets.txt",folder)<0)return 0;
    FILE*f=_wfopen(p,L"rb");if(!f)return 0;
    while(n<64 && fscanf(f,"%u %u %u %u",&a,&b,&c,&d)==4)list[n++]=(Guid){a,b,c,d};
    fclose(f);AcquireSRWLockExclusive(&lock);memcpy(targets,list,(size_t)n*sizeof(Guid));target_count=n;ReleaseSRWLockExclusive(&lock);return 1;
}
__declspec(dllexport) int robocop_check_file(const wchar_t* path,char* report,uint32_t capacity){
    if(!report || capacity<1)return 0;
    HANDLE f=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL);
    if(f==INVALID_HANDLE_VALUE){snprintf(report,capacity,"Cannot read game executable");return 0;}
    LARGE_INTEGER length;int result=0;HANDLE mapping=NULL;const unsigned char* data=NULL;
    if(!GetFileSizeEx(f,&length) || length.QuadPart<64 || (uint64_t)length.QuadPart>SIZE_MAX){snprintf(report,capacity,"Invalid executable size");goto finish;}
    mapping=CreateFileMappingW(f,NULL,PAGE_READONLY,0,0,NULL);
    if(!mapping){snprintf(report,capacity,"Cannot map game executable");goto finish;}
    data=MapViewOfFile(mapping,FILE_MAP_READ,0,0,0);
    if(!data){snprintf(report,capacity,"Cannot view game executable");goto finish;}
    RcpImage im;uint32_t addresses[4];
    if(!rcp_open(&im,data,(size_t)length.QuadPart,0)){snprintf(report,capacity,"Not a supported Windows x64 game executable");goto finish;}
    result=rcp_resolve(&im,addresses,report,capacity);
finish:
    if(data)UnmapViewOfFile(data);if(mapping)CloseHandle(mapping);CloseHandle(f);return result;
}
static int freeze(HANDLE* threads,size_t* count){
    *count=0;HANDLE snap=CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD,0);
    if(snap==INVALID_HANDLE_VALUE)return 0;
    THREADENTRY32 t={.dwSize=sizeof(t)};int valid=1;
    if(!Thread32First(snap,&t)){CloseHandle(snap);return 0;}
    do{
        if(t.th32OwnerProcessID==GetCurrentProcessId() && t.th32ThreadID!=GetCurrentThreadId()){
            if(*count>=512){valid=0;break;}
            HANDLE h=OpenThread(THREAD_SUSPEND_RESUME|THREAD_GET_CONTEXT|THREAD_QUERY_INFORMATION,FALSE,t.th32ThreadID);
            if(!h){valid=0;break;}threads[(*count)++]=h;
        }
    }while(Thread32Next(snap,&t));CloseHandle(snap);
    if(!valid){for(size_t i=0;i<*count;i++)CloseHandle(threads[i]);*count=0;return 0;}
    size_t suspended=0;
    for(;suspended<*count;suspended++){
        if(SuspendThread(threads[suspended])==(DWORD)-1){valid=0;break;}
    }
    if(valid)for(size_t i=0;i<*count;i++){
        CONTEXT c={.ContextFlags=CONTEXT_CONTROL};
        if(!GetThreadContext(threads[i],&c)){valid=0;break;}
        for(int k=0;k<4;k++)if(c.Rip>=(DWORD64)hooks[k].entry && c.Rip<(DWORD64)(hooks[k].entry+hooks[k].length)){valid=0;break;}
        if(!valid)break;
    }
    if(!valid){for(size_t i=0;i<suspended;i++)ResumeThread(threads[i]);for(size_t i=0;i<*count;i++)CloseHandle(threads[i]);*count=0;return 0;}
    return 1;
}
static void thaw(HANDLE* threads,size_t count){for(size_t i=0;i<count;i++)ResumeThread(threads[i]);for(size_t i=0;i<count;i++)CloseHandle(threads[i]);}
__declspec(dllexport) int robocop_refresh(void* state){
    (void)state;
    if(!load_targets()){fail("target file unavailable");return 0;}
    if(!installed){status(failure);return 0;}
    for(int i=0;i<4;i++)if(memcmp(hooks[i].entry,hooks[i].patch,hooks[i].length)){fail("another patch replaced a RoboCop hook; restart with the conflict removed");return 0;}
    status("READY");return 0;
}
__declspec(dllexport) int robocop_alert(void* state){
    (void)state;
    if(InterlockedCompareExchange(&warned,1,0)==0)MessageBoxW(NULL,L"RoboCop's patrol protection could not be verified.\n\nThe mod is requesting a game pause. Keep Alex Murphy off patrol until compatibility is restored.\n\nSee RoboCopGameplay/native_status.txt for the exact error. Restart after installing a compatible release.",L"RoboCop: protection unavailable",MB_OK|MB_ICONERROR|MB_SETFOREGROUND);
    return 0;
}
__declspec(dllexport) int robocop_init(void* state){
    (void)state;
    if(!module){
        if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,(LPCWSTR)&robocop_init,&module))return 0;
        DWORD n=GetModuleFileNameW(module,folder,32768);if(!n || n>=32768)return 0;
        wchar_t* slash=wcsrchr(folder,L'\\');if(!slash)return 0;*slash=0;
    }
    if(!load_targets()){fail("target file unavailable");return 0;}
    if(installed)return robocop_refresh(state);
    unsigned char* base=(unsigned char*)GetModuleHandleW(NULL);MODULEINFO info;
    if(!GetModuleInformation(GetCurrentProcess(),(HMODULE)base,&info,sizeof(info))){fail("cannot inspect game module");return 0;}
    RcpImage im;uint32_t addresses[4];char report[512];
    if(!rcp_open(&im,base,info.SizeOfImage,1)){fail("invalid game image");return 0;}
    if(!rcp_resolve(&im,addresses,report,sizeof(report))){fail(report);return 0;}
    void* replacements[4]={(void*)on_salary,(void*)on_death,(void*)on_params,(void*)on_complete};
    for(int i=0;i<4;i++){
        Hook*h=&hooks[i];h->entry=base+addresses[i];h->length=rcp_profiles[i].patch;
        h->trampoline=VirtualAlloc(NULL,128,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
        if(!h->trampoline){fail("trampoline allocation failed");goto cleanup;}
        memcpy(h->saved,h->entry,h->length);memcpy(h->trampoline,h->entry,h->length);jump(h->trampoline+h->length,h->entry+h->length);
        memset(h->patch,0x90,sizeof(h->patch));jump(h->patch,replacements[i]);
        DWORD old;
        if(!VirtualProtect(h->trampoline,128,PAGE_EXECUTE_READ,&old)){fail("trampoline protection failed");goto cleanup;}
        FlushInstructionCache(GetCurrentProcess(),h->trampoline,128);
        MEMORY_BASIC_INFORMATION region;
        if(!VirtualQuery(h->entry,&region,sizeof(region)) || !(region.Protect & (PAGE_EXECUTE|PAGE_EXECUTE_READ|PAGE_EXECUTE_READWRITE|PAGE_EXECUTE_WRITECOPY))){fail("hook page is not executable");goto cleanup;}
        h->protection=region.Protect;
    }
    original_salary=(void*)hooks[0].trampoline;original_death=(void*)hooks[1].trampoline;original_params=(void*)hooks[2].trampoline;original_complete=(void*)hooks[3].trampoline;
    HANDLE threads[512];size_t count=0;
    int frozen=0;for(int attempt=0;attempt<5 && !frozen;attempt++){frozen=freeze(threads,&count);if(!frozen)Sleep(1);}
    if(!frozen){fail("could not safely suspend threads for installation; restart the game");goto cleanup;}
    int protected_count=0;
    for(int i=0;i<4;i++){
        Hook*h=&hooks[i];DWORD previous;
        if(memcmp(h->entry,h->saved,h->length) || !VirtualProtect(h->entry,h->length,PAGE_EXECUTE_READWRITE,&previous))break;
        protected_count++;
    }
    if(protected_count==4){
        for(int i=0;i<4;i++){Hook*h=&hooks[i];memcpy(h->entry,h->patch,h->length);FlushInstructionCache(GetCurrentProcess(),h->entry,h->length);}
        installed=1;
    }
    for(int i=0;i<protected_count;i++){DWORD ignored;VirtualProtect(hooks[i].entry,hooks[i].length,hooks[i].protection,&ignored);}
    thaw(threads,count);
    if(!installed){fail("hook installation stopped before writing code");goto cleanup;}
    failure[0]=0;status("READY");return 0;
cleanup:
    for(int i=0;i<4;i++)if(hooks[i].trampoline){VirtualFree(hooks[i].trampoline,0,MEM_RELEASE);hooks[i].trampoline=NULL;}
    return 0;
}
