--========================================================
-- @title JKK_TrackManager_TrackActivation
-- @author Junki Kim
-- @version 1.0.3
-- @noindex
--========================================================
local action_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local root_dir   = action_dir:gsub("[^\\/]+[\\/]$", "")
local Core       = dofile(root_dir .. "Modules/JKK_TrackManager_Core.lua")

reaper.defer(function() end)
Core.ToggleSelectedTracksActive()
