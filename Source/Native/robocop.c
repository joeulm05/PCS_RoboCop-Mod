/* RoboCop Gameplay v0.4 | Author: Joe "Gambit" Bradford */
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stddef.h>
typedef struct { uint32_t a,b,c,d; } Guid;
typedef struct { Guid* data; int32_t count,capacity; } GuidArray;
typedef struct { GuidArray officers; unsigned char padding[48]; float success; } Mission;
_Static_assert(offsetof(Mission,success)==0x40,"mission layout");
static Guid targets[64];
static int target_count, installed;
static SRWLOCK lock=SRWLOCK_INIT;
static HMODULE module;
static char folder[MAX_PATH];
static int matches(const Guid* g) {
    int result=0;
    if(!g) return 0;
    AcquireSRWLockShared(&lock);
    for(int i=0;i<target_count;i++) if(!memcmp(g,&targets[i],16)){result=1;break;}
    ReleaseSRWLockShared(&lock);
    return result;
}
static int contains(const GuidArray* a) {
    if(!a || !a->data || a->count<1 || a->count>64 || a->capacity<a->count) return 0;
    for(int i=0;i<a->count;i++) if(matches(a->data+i)) return 1;
    return 0;
}
static float (*original_salary)(void*,Guid*);
static void (*original_death)(void*,Guid*);
static void (*original_params)(void*,int*,float*,float*,GuidArray*,void*,void*,void*);
static void (*original_complete)(void*,Mission*);
static float on_salary(void* self,Guid* id){return matches(id)?100.f:original_salary(self,id);}
static void on_death(void* self,Guid* id){if(!matches(id))original_death(self,id);}
static void on_params(void* self,int* duration,float* danger,float* success,GuidArray* officers,void* caseid,void* equipment,void* vehicle){
    original_params(self,duration,danger,success,officers,caseid,equipment,vehicle);
    if(success && contains(officers)) *success=10.f;
}
static void on_complete(void* self,Mission* mission){
    if(mission && contains(&mission->officers)) mission->success=10.f;
    original_complete(self,mission);
}
typedef struct {size_t rva,length;const unsigned char* verify;size_t verify_size;void* replacement;unsigned char* entry;unsigned char* trampoline;unsigned char saved[32];} Hook;
#include "build_manifest.h"
static void status(const char* message){char p[MAX_PATH];snprintf(p,sizeof(p),"%s/native_status.txt",folder);FILE*f=fopen(p,"wb");if(f){fputs(message,f);fclose(f);}}
static void jump(unsigned char* where,void* to){unsigned char op[6]={0xff,0x25,0,0,0,0};memcpy(where,op,6);memcpy(where+6,&to,8);}
static int load_targets(void){
    char p[MAX_PATH];Guid list[64];int n=0;unsigned int a,b,c,d;
    snprintf(p,sizeof(p),"%s/targets.txt",folder);FILE*f=fopen(p,"rb");if(!f)return 0;
    while(n<64 && fscanf(f,"%u %u %u %u",&a,&b,&c,&d)==4) list[n++]=(Guid){a,b,c,d};
    fclose(f);AcquireSRWLockExclusive(&lock);memcpy(targets,list,n*sizeof(Guid));target_count=n;ReleaseSRWLockExclusive(&lock);return 1;
}
__declspec(dllexport) int robocop_refresh(void* state){(void)state;if(load_targets())status(installed?"READY":"NOT_INSTALLED");else status("ERROR: target file unavailable");return 0;}
__declspec(dllexport) int robocop_init(void* state){
    (void)state;
    if(!module){
        if(!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,(LPCSTR)&robocop_init,&module))return 0;
        DWORD n=GetModuleFileNameA(module,folder,sizeof(folder));if(!n || n>=sizeof(folder))return 0;
        char* slash=strrchr(folder,'\\');if(!slash)return 0;*slash=0;
    }
    if(!load_targets()){status("ERROR: target file unavailable");return 0;}
    if(installed){status("READY");return 0;}
    unsigned char* base=(unsigned char*)GetModuleHandleA(0);
    IMAGE_DOS_HEADER* dos=(IMAGE_DOS_HEADER*)base;IMAGE_NT_HEADERS64* nt=(IMAGE_NT_HEADERS64*)(base+dos->e_lfanew);
    if(nt->FileHeader.TimeDateStamp!=BUILD_TIMESTAMP || nt->OptionalHeader.SizeOfImage!=BUILD_SIZE){status("ERROR: game build mismatch; no hooks installed");return 0;}
    for(int i=0;i<4;i++){
        Hook*h=&hooks[i];h->entry=base+h->rva;
        if(memcmp(h->entry,h->verify,h->verify_size)){status("ERROR: native function mismatch; no hooks installed");return 0;}
    }
    for(int i=0;i<4;i++){
        Hook*h=&hooks[i];h->trampoline=VirtualAlloc(0,128,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
        if(!h->trampoline){status("ERROR: trampoline allocation failed");return 0;}
        memcpy(h->saved,h->entry,h->length);memcpy(h->trampoline,h->entry,h->length);jump(h->trampoline+h->length,h->entry+h->length);
        DWORD old;if(!VirtualProtect(h->trampoline,128,PAGE_EXECUTE_READ,&old)){status("ERROR: trampoline protection failed");return 0;}
        FlushInstructionCache(GetCurrentProcess(),h->trampoline,128);
    }
    original_salary=(void*)hooks[0].trampoline;original_death=(void*)hooks[1].trampoline;original_params=(void*)hooks[2].trampoline;original_complete=(void*)hooks[3].trampoline;
    int done=0;
    for(int i=0;i<4;i++){
        Hook*h=&hooks[i];DWORD old;
        if(!VirtualProtect(h->entry,h->length,PAGE_EXECUTE_READWRITE,&old))break;
        jump(h->entry,h->replacement);if(h->length>14)memset(h->entry+14,0x90,h->length-14);
        DWORD ignored;VirtualProtect(h->entry,h->length,old,&ignored);FlushInstructionCache(GetCurrentProcess(),h->entry,h->length);done++;
    }
    if(done!=4){
        for(int i=0;i<done;i++){Hook*h=&hooks[i];DWORD old,ignored;if(VirtualProtect(h->entry,h->length,PAGE_EXECUTE_READWRITE,&old)){memcpy(h->entry,h->saved,h->length);VirtualProtect(h->entry,h->length,old,&ignored);FlushInstructionCache(GetCurrentProcess(),h->entry,h->length);}}
        status("ERROR: hook installation failed; rollback attempted");return 0;
    }
    installed=1;status("READY");return 0;
}
