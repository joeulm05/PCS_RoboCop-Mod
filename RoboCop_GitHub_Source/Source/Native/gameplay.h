/* RoboCop Gameplay Rules | Author: Joe "Gambit" Bradford */
static float (*original_salary)(void*,Guid*);
static void (*original_death)(void*,Guid*);
static void (*original_params)(void*,int*,float*,float*,GuidArray*,void*,void*,void*);
static void (*original_complete)(void*,Mission*);
static float on_salary(void* self,Guid* id){return matches(id)?100.f:original_salary(self,id);}
static void on_death(void* self,Guid* id){if(!matches(id))original_death(self,id);}
static void on_params(void* self,int* duration,float* danger,float* success,GuidArray* officers,void* caseid,void* equipment,void* vehicle){
    original_params(self,duration,danger,success,officers,caseid,equipment,vehicle);
    if(success && contains(officers))*success=10.f;
}
static void on_complete(void* self,Mission* mission){
    if(mission && contains(&mission->officers))mission->success=10.f;
    original_complete(self,mission);
}
