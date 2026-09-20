-- RoboCop Gameplay v1.0.1 | Author: Joe "Gambit" Bradford
local source=debug.getinfo(1,'S').source:gsub('^@',''):gsub('\\','/')
local folder=assert(source:match('^(.*)/Scripts/[^/]+$'),'RoboCopGameplay: cannot locate mod folder')
local targets,lastIDs={},nil
local ready,loading=false,false
local missions={}
local nativeRefresh
local nativeAlert
local healthTicks=0
local messages={}
local model='/Game/ProjectPreasidium/Art/Characters/ControlRig_Characters/Workers/Worker_02_M/Uniform1/NPC_Worker_02_M_Uniform1.NPC_Worker_02_M_Uniform1'
local function log(s) print('[RoboCopGameplay] '..tostring(s)..'\n') end
local function once(k,s) if messages[k]~=s then messages[k]=s;log(s) end end
local function unwrap(v) local ok,x=pcall(function()return v:get()end);if ok then return x end;return v end
local function valid(v) local ok,x=pcall(function()return v:IsValid()end);return ok and x==true end
local function text(v) local ok,x=pcall(function()return v:ToString()end);return ok and tostring(x) or tostring(v) end
local function numbers(v)return {v.A%4294967296,v.B%4294967296,v.C%4294967296,v.D%4294967296}end
local function guid(v)return table.concat(numbers(v),' ')end
local function each(m,f)m:ForEach(function(k,v)f(unwrap(k),unwrap(v))end)end
local function writeIDs(ids)
    local f=assert(io.open(folder..'/targets.txt','wb'));assert(f:write(ids));assert(f:close())
end
local function native(ids)
    healthTicks=healthTicks+1
    if lastIDs==ids and ready and healthTicks<5 then return true end
    healthTicks=0
    if lastIDs~=ids then writeIDs(ids) end
    if not nativeRefresh then
        local init,err=package.loadlib(folder..'/robocop_native.dll','robocop_init');assert(init,err);init()
        nativeRefresh=assert(package.loadlib(folder..'/robocop_native.dll','robocop_refresh'))
        nativeAlert=assert(package.loadlib(folder..'/robocop_native.dll','robocop_alert'))
    else nativeRefresh() end
    local f=assert(io.open(folder..'/native_status.txt','rb'));local status=f:read('*a');f:close()
    ready=status=='READY';once('native','Native helper: '..status)
    if ready then lastIDs=ids end
    return ready
end
local function protectionFailure(context,reason)
    ready=false
    once('protection','PROTECTION UNAVAILABLE: '..tostring(reason)..'; requesting a game pause. Keep Alex off patrol until repaired.')
    local ok,result=pcall(function()
        local clock=StaticFindObject('/Script/Engine.Default__GameplayStatics')
        if valid(clock) then return clock:SetGamePaused(context,true) end
    end)
    if not ok or result~=true then once('pause','Could not confirm a game pause. Return to the main menu; death protection is unavailable.') end
    if nativeAlert then pcall(nativeAlert) end
end
local function patrolTimers()
    local clock=StaticFindObject('/Script/Engine.Default__GameplayStatics')
    if not valid(clock) then return end
    local seen={}
    for _,system in ipairs(FindAllOf('PP_PatrolOfficerSubsystem') or {}) do
        if valid(system) then
            local now=clock:GetTimeSeconds(system)
            local world=text(system:GetFullName())
            local due=false
            each(system.DispatchMissions,function(_,mission)
                local ids,hasRobo={},false
                each(mission.Officers,function(_,id)
                    local key=guid(id);ids[#ids+1]=key
                    if targets[key] then hasRobo=true end
                end)
                if not hasRobo then return end
                table.sort(ids)
                local key=world..'|'..text(mission.CaseID)..'|'..table.concat(ids,';')
                seen[key]=true
                local record=missions[key]
                if not record or now<record.started then
                    record={started=now};missions[key]=record
                    log('30-second patrol timer started | case='..text(mission.CaseID))
                end
                if now-record.started>=30 then
                    mission.MinutesRemaining=0;due=true
                    if not record.reported then record.reported=true;log('30 seconds elapsed; requesting normal mission completion | case='..text(mission.CaseID)) end
                else
                    local scale=system.TimeSystem.DayTimeScale
                    assert(type(scale)=="number" and scale>=0 and scale<=3600,"Day-time scale unavailable")
                    mission.MinutesRemaining=math.max(2,math.ceil((30-(now-record.started))*scale/60)+1)
                end
            end)
            if due then system:OnMinutesPassed(0) end
        end
    end
    for key in pairs(missions) do if not seen[key] then missions[key]=nil end end
end
local function service()
    if loading then return end
    local updateContext
    local ok,err=pcall(function()
        local library=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary');if not valid(library) then return end
        local active={};local context
        for _,w in ipairs(FindAllOf('PP_WorkerSubsystem') or {}) do
            if valid(w) then
                context=w
                updateContext=w
                for _,field in ipairs({'HiredWorkers','WorkersForHire'})do each(w[field],function(_,id)active[guid(id)]=true end)end
            end
        end
        if not context then return end
        local found={}
        local systems=FindAllOf('PP_NPCDataSubsystem') or {}
        for _,d in ipairs(systems)do if valid(d)then
            for _,field in ipairs({'BaseDataPersistent','BaseDataTransient'})do each(d[field],function(id,b)
                local key=guid(id)
                if active[key] and text(library:Conv_SoftObjectReferenceToString(b.CharacterMesh))==model then found[key]=true end
            end)end
        end end
        local rows={};for key in pairs(found)do rows[#rows+1]=key end;table.sort(rows)
        if #rows==0 then
            if lastIDs and lastIDs~='' then native('') end
            targets={};once('identity','Waiting for RoboCop in the hired or hireable worker list.');return
        end
        targets=found
        local checked,active=pcall(native,table.concat(rows,'\n')..'\n')
        if not checked or not active then protectionFailure(context,checked and 'native compatibility check failed' or active);return end
        once('identity','Alex Murphy target identified; native wage/success/death protection active.')
        for _,d in ipairs(systems)do if valid(d)then
            for _,field in ipairs({'BaseDataPersistent','BaseDataTransient'})do each(d[field],function(id,b)
                if targets[guid(id)]then b.Name='Alex';b.Surname='Murphy' end
            end)end
            for _,field in ipairs({'WorkerDataPersistent','WorkerDataTransient'})do each(d[field],function(id,w)
                if targets[guid(id)]then
                    w.Level.Level=5;w.Level.Xp=1000;w.Morale=100
                    each(w.Stats,function(_,stat)stat.Level=10;stat.Xp=1500 end)
                    assert(w.Level.Level==5 and w.Morale==100,'Worker stat write did not persist')
                end
            end)end
        end end
        patrolTimers()
        once('stats','Name and maximum stats applied. Daily wage is $100 while this mod is active.')
    end)
    if not ok then
        once('service-error','Update failed: '..tostring(err))
        if updateContext then protectionFailure(updateContext,err) end
    end
end
local function initialTargets()
    local f=io.open(folder..'/targets.txt','rb')
    if not f then return '' end
    local contents=f:read('*a');f:close()
    if not contents or #contents>4096 then return '' end
    local rows={}
    for line in contents:gmatch('[^\r\n]+') do
        local a,b,c,d=line:match('^(%d+) (%d+) (%d+) (%d+)$')
        if not a then return '' end
        for _,part in ipairs({a,b,c,d}) do if #part>10 or tonumber(part)>4294967295 then return '' end end
        rows[#rows+1]=line
        if #rows>64 then return '' end
    end
    return #rows>0 and table.concat(rows,'\n')..'\n' or ''
end
local ok,err=pcall(function()
    RegisterLoadMapPreHook(function()loading=true;targets={};lastIDs=nil;missions={} end)
    RegisterLoadMapPostHook(function()loading=false;service() end)
    local started,startError=pcall(native,initialTargets())
    if not started then once('native-startup','Native startup failed: '..tostring(startError)) end
    assert(type(LoopInGameThreadWithDelay(1000,service))=='number','Game-thread timer unavailable')
end)
if not ok then log('INACTIVE: '..tostring(err))else log('v1.0.1 loaded; verified native perks and 30-second patrol timer; portrait handled separately.')end
