/* RoboCop Compatibility Reader | Author: Joe "Gambit" Bradford */
#ifndef RCP_COMPATIBILITY_H
#define RCP_COMPATIBILITY_H
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
typedef struct { uint32_t begin,end; } RcpSegment;
typedef struct { const char* name; const unsigned char* pattern; const unsigned char* mask; size_t length,patch; const RcpSegment* segments; size_t segment_count; } RcpProfile;
#include "profiles.h"
typedef struct { const unsigned char* data; size_t size; int mapped; uint32_t image_size; size_t sections; uint16_t section_count; uint32_t exception_rva,exception_size; } RcpImage;
static uint16_t rcp_u16(const unsigned char* p){uint16_t v;memcpy(&v,p,2);return v;}
static uint32_t rcp_u32(const unsigned char* p){uint32_t v;memcpy(&v,p,4);return v;}
static int rcp_range(size_t off,size_t n,size_t total){return off<=total && n<=total-off;}
static const unsigned char* rcp_rva(const RcpImage* im,uint32_t rva,size_t length,int executable){
    if(!rcp_range(rva,length,im->image_size))return NULL;
    for(size_t i=0;i<im->section_count;i++){
        const unsigned char* s=im->data+im->sections+i*40;
        uint32_t va=rcp_u32(s+12),vs=rcp_u32(s+8),raw=rcp_u32(s+16),at=rcp_u32(s+20),flags=rcp_u32(s+36);
        size_t span=im->mapped?(vs>raw?vs:raw):raw;
        if(rva<va || !rcp_range((size_t)rva-va,length,span))continue;
        if(executable && !(flags&0x20000000u))return NULL;
        size_t off=im->mapped?rva:(size_t)at+rva-va;
        return rcp_range(off,length,im->size)?im->data+off:NULL;
    }
    return NULL;
}
static int rcp_open(RcpImage* im,const unsigned char* data,size_t size,int mapped){
    memset(im,0,sizeof(*im));
    if(!data || size<64 || rcp_u16(data)!=0x5a4d)return 0;
    uint32_t nt=rcp_u32(data+60);
    if(!rcp_range(nt,24,size) || rcp_u32(data+nt)!=0x4550 || rcp_u16(data+nt+4)!=0x8664)return 0;
    uint16_t optional=rcp_u16(data+nt+20),count=rcp_u16(data+nt+6);
    size_t op=(size_t)nt+24;
    if(optional<144 || !rcp_range(op,optional,size) || rcp_u16(data+op)!=0x20b || rcp_u32(data+op+108)<4 || count<1 || count>96)return 0;
    size_t sections=op+optional;
    if(!rcp_range(sections,(size_t)count*40,size))return 0;
    im->data=data;im->size=size;im->mapped=mapped;im->sections=sections;im->section_count=count;
    im->image_size=rcp_u32(data+op+56);im->exception_rva=rcp_u32(data+op+136);im->exception_size=rcp_u32(data+op+140);
    if(im->image_size<4096 || im->exception_size==0 || im->exception_size%12 || im->exception_size>12000000)return 0;
    if(mapped && size<im->image_size)return 0;
    return rcp_rva(im,im->exception_rva,im->exception_size,0)!=NULL;
}
static int rcp_resolve(const RcpImage* im,uint32_t* results,char* report,size_t capacity){
    const unsigned char* table=rcp_rva(im,im->exception_rva,im->exception_size,0);
    if(!table){snprintf(report,capacity,"Invalid exception directory");return 0;}
    size_t count=im->exception_size/12;
    for(size_t k=0;k<RCP_PROFILE_COUNT;k++){
        const RcpProfile* p=&rcp_profiles[k];unsigned matches=0;uint32_t found=0;
        for(size_t i=0;i<count;i++){
            uint32_t rva=rcp_u32(table+i*12),end=rcp_u32(table+i*12+4);
            if(end<rva || end-rva!=p->segments[0].end || p->segment_count>count-i)continue;
            const unsigned char* code=rcp_rva(im,rva,p->length,1);
            if(!code || memcmp(code,p->pattern,p->patch))continue;
            int valid=1;
            for(size_t s=0;s<p->segment_count;s++){
                if((uint64_t)rva+p->segments[s].end>UINT32_MAX || rcp_u32(table+(i+s)*12)!=rva+p->segments[s].begin || rcp_u32(table+(i+s)*12+4)!=rva+p->segments[s].end){valid=0;break;}
            }
            if(!valid)continue;
            for(size_t b=0;b<p->length;b++)if((code[b]&p->mask[b])!=p->pattern[b]){valid=0;break;}
            if(valid){found=rva;if(++matches>1)break;}
        }
        if(matches!=1){snprintf(report,capacity,"%s: expected one verified function, found %u; protection unavailable",p->name,matches);return 0;}
        results[k]=found;
    }
    snprintf(report,capacity,"VERIFIED | salary=%08x | death=%08x | success=%08x | completion=%08x",results[0],results[1],results[2],results[3]);return 1;
}
#endif
