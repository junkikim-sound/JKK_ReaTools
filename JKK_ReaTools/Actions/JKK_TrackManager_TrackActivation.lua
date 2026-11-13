--========================================================
-- @title JKK_TrackManager_TrackActivation
-- @author Junki Kim
-- @version 1.0.0
--========================================================
local RPR = reaper
local action_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local root_dir   = action_dir:gsub("[^\\/]+[\\/]$", "")
local Core       = dofile(root_dir .. "Modules/JKK_TrackManager_Core.lua")

local sel_count = RPR.CountSelectedTracks(0)
if sel_count == 0 then return end

local any_active = false
for i = 0, sel_count - 1 do
    local tr = RPR.GetSelectedTrack(0, i)
    if tr and Core.IsTrackActive(tr) then
        any_active = true
        break
    end
end

Core.SetSelectedTracksActive(not any_active, "JKK Track Manager: Toggle Selected Tracks Active")