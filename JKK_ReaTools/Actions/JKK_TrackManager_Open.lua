--========================================================
-- @title JKK_TrackManager_Open
-- @author Junki Kim (JKK)
-- @version 1.0.1
--========================================================

local RPR = reaper

local action_dir  = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local root_dir    = action_dir:gsub("[^\\/]+[\\/]$", "")
local main_script = root_dir .. "JKK_TrackManager.lua"

local hb = tonumber(RPR.GetExtState("JKK_TRACK_MGR", "HEARTBEAT")) or 0
if hb > 0 and (RPR.time_precise() - hb) < 0.5 then
    RPR.SetExtState("JKK_TRACK_MGR", "FOCUS_REQ", "1", false)
else
    if RPR.file_exists(main_script) then
        local cmd_id = RPR.AddRemoveReaScript(true, 0, main_script, true)
        if cmd_id and cmd_id ~= 0 then
            RPR.Main_OnCommand(cmd_id, 0)
        end
    else
        RPR.ShowMessageBox("JKK_TrackManager.lua 파일을 찾을 수 없습니다.\n경로: " .. main_script, "JKK Track Manager", 0)
    end
end