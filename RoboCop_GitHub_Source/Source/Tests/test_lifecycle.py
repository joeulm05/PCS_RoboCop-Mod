# RoboCop Lifecycle Tests | Author: Joe "Gambit" Bradford
from pathlib import Path
from lupa import LuaRuntime

path=Path(__file__).resolve().parents[2]/'Payload/RoboCopGameplay/Scripts/main.lua'
source=path.read_text()
lua=LuaRuntime()
lua.execute('''
function object(t)t=t or {};function t:IsValid()return true end;return t end
function collection(rows)return {ForEach=function(self,fn)for _,row in ipairs(rows)do fn(row[1],row[2])end end}end
robo={A=1,B=2,C=3,D=4};other={A=9,B=8,C=7,D=6}
local model='/Game/ProjectPreasidium/Art/Characters/ControlRig_Characters/Workers/Worker_02_M/Uniform1/NPC_Worker_02_M_Uniform1.NPC_Worker_02_M_Uniform1'
base={CharacterMesh=model,Name='Original',Surname='Officer'}
otherbase={CharacterMesh='other',Name='Keep',Surname='Name'}
stat={Level=1,Xp=0};worker={Level={Level=1,Xp=0},Morale=5,Stats=collection({{'stat',stat}})}
otherworker={Level={Level=2,Xp=7},Morale=15,Stats=collection({})}
data=object({BaseDataPersistent=collection({{robo,base},{other,otherbase}}),BaseDataTransient=collection({}),WorkerDataPersistent=collection({{robo,worker},{other,otherworker}}),WorkerDataTransient=collection({})})
workers=object({HiredWorkers=collection({{1,robo},{2,other}}),WorkersForHire=collection({})})
mission={Officers=collection({{1,robo},{2,other}}),CaseID='Case42',MinutesRemaining=99}
patrol=object({DispatchMissions=collection({{1,mission}}),TimeSystem={DayTimeScale=120}})
function patrol:GetFullName()return 'world.patrol'end
completions=0
function patrol:OnMinutesPassed(n)assert(n==0);completions=completions+1;self.DispatchMissions=collection({})end
now=0;pauses=0;alerts=0;native_calls=0;native_status='READY';missing_dll=false
clock=object({GetTimeSeconds=function()return now end,SetGamePaused=function(self,ctx,value)assert(ctx==workers and value);pauses=pauses+1;return true end})
softref=object({Conv_SoftObjectReferenceToString=function(self,value)return value end})
function StaticFindObject(name)if name:find('GameplayStatics')then return clock else return softref end end
function FindAllOf(name)if name=='PP_WorkerSubsystem'then return {workers} elseif name=='PP_NPCDataSubsystem'then return {data} else return {patrol}end end
function RegisterLoadMapPreHook(fn)pre=fn end
function RegisterLoadMapPostHook(fn)post=fn end
function LoopInGameThreadWithDelay(delay,fn)assert(delay==1000);tick=fn;return 1 end
files={}
io.open=function(path,mode)
 if mode=='wb'then return {write=function(self,value)files[path]=value;return self end,close=function()return true end}end
 return {read=function()return native_status end,close=function()return true end}
end
package.loadlib=function(path,entry)
 if missing_dll then return nil,'mock DLL unavailable'end
 if entry=='robocop_alert'then return function()alerts=alerts+1 end end
 return function()native_calls=native_calls+1 end
end
''')
lua.execute('assert(load(..., "@" .. select(2,...)))()',source,str(path))
lua.execute('''
assert(native_calls>=1);tick();assert(base.Name=='Alex' and base.Surname=='Murphy');assert(worker.Level.Level==5 and stat.Level==10 and worker.Morale==100)
assert(otherbase.Name=='Keep' and otherworker.Level.Level==2 and otherworker.Morale==15)
now=29.9;tick();assert(completions==0);now=30;tick();assert(completions==1)
local calls=native_calls;pre();tick();assert(native_calls==calls);post();tick();assert(native_calls>calls)
native_status='ERROR: death: expected one verified function, found 0';for i=1,5 do tick()end
assert(pauses>0 and alerts>0)
local before=pauses;tick();assert(pauses>before)
print('PASS: full Lua lifecycle, identity/stats, unrelated worker, 30 seconds, load transition, compatibility failure pause and alert')
''')
lua.execute("missing_dll=true;pauses=0")
lua.execute('assert(load(..., "@" .. select(2,...)))()',source,str(path))
lua.execute("tick();assert(pauses==1);print('PASS: missing native DLL requests a pause without asserting protection')")
