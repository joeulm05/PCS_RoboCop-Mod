# RoboCop Patrol Timer Tests | Author: Joe "Gambit" Bradford
from pathlib import Path
from lupa import LuaRuntime
source=(Path(__file__).resolve().parents[2]/'Payload/RoboCopGameplay/Scripts/main.lua').read_text()
body=source[source.index('local function patrolTimers()'):source.index('local function service()')]
lua=LuaRuntime()
lua.execute('''
local missions={}
local targets={robo=true}
local function valid(x)return x~=nil end
local function text(x)return tostring(x)end
local function guid(x)return x end
local function each(x,f)for k,v in ipairs(x)do f(k,v)end end
local function log(x)end
local now=0
local robo={Officers={'other','robo'},CaseID='caseA',MinutesRemaining=99}
local other={Officers={'other'},CaseID='caseB',MinutesRemaining=77}
local system={DispatchMissions={robo,other},TimeSystem={DayTimeScale=120}}
function system:GetFullName()return 'world.patrol'end
local completions=0
function system:OnMinutesPassed(n)assert(n==0);assert(other.MinutesRemaining==77);completions=completions+1;self.DispatchMissions={other}end
function StaticFindObject()return {GetTimeSeconds=function()return now end}end
function FindAllOf()return {system}end
''' + body + '''
patrolTimers();assert(completions==0 and other.MinutesRemaining==77)
now=29.9;patrolTimers();assert(completions==0 and robo.MinutesRemaining>0)
patrolTimers();assert(completions==0)
now=30;patrolTimers();assert(completions==1 and robo.MinutesRemaining==0)
now=60;patrolTimers();assert(completions==1 and next(missions)==nil)
print('PASS: 30-second boundary, paused clock, mixed party, unrelated patrol unchanged, no repeated completion')
''')
