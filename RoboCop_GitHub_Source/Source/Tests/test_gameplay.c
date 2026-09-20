/* RoboCop Gameplay Tests | Author: Joe "Gambit" Bradford */
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
typedef struct {uint32_t a,b,c,d;} Guid;
typedef struct {Guid* data;int32_t count,capacity;} GuidArray;
typedef struct {GuidArray officers;unsigned char padding[48];float success;} Mission;
_Static_assert(offsetof(Mission,success)==0x40,"mission layout");
static Guid robo={1,2,3,4},other={9,8,7,6};
static int matches(const Guid* id){return id && !memcmp(id,&robo,sizeof(Guid));}
static int contains(const GuidArray* a){if(!a || !a->data || a->count<1 || a->count>64 || a->capacity<a->count)return 0;for(int i=0;i<a->count;i++)if(matches(a->data+i))return 1;return 0;}
#include "gameplay.h"
static int deaths,completed,salaries;
static float last_success;
static float salary(void*s,Guid*id){(void)s;(void)id;salaries++;return 75;}
static void death(void*s,Guid*id){(void)s;assert(id==&other);deaths++;}
static void params(void*s,int*d,float*r,float*c,GuidArray*a,void*b,void*e,void*v){(void)s;(void)a;(void)b;(void)e;(void)v;*d=90;*r=0.4f;*c=0.3f;}
static void complete(void*s,Mission*m){(void)s;completed++;last_success=m->success;}
int main(void){
    original_salary=salary;original_death=death;original_params=params;original_complete=complete;
    assert(on_salary(NULL,&robo)==100 && salaries==0);assert(on_salary(NULL,&other)==75 && salaries==1);
    for(int i=0;i<100;i++)on_death(NULL,&robo);assert(deaths==0);on_death(NULL,&other);assert(deaths==1);
    Guid ids[]={other,robo};GuidArray party={ids,2,2};int duration;float danger,success;
    on_params(NULL,&duration,&danger,&success,&party,NULL,NULL,NULL);assert(success==10 && duration==90 && danger==0.4f);
    Mission mission={.officers=party,.success=0.1f};on_complete(NULL,&mission);assert(completed==1 && last_success==10);
    party.count=1;on_params(NULL,&duration,&danger,&success,&party,NULL,NULL,NULL);assert(success==0.3f);
    mission.officers=party;mission.success=0.2f;on_complete(NULL,&mission);assert(completed==2 && last_success==0.2f);
    puts("PASS: $100 wage; 100 blocked RoboCop deaths; other officer unchanged; 1000% parameters and completion; unrelated mission unchanged");
}
