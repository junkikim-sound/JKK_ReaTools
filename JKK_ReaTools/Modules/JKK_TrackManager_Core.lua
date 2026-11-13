--========================================================
-- @title JKK_TrackManager_Core
-- @author Junki Kim
-- @noindex
--========================================================

local RPR = reaper
local Core = {}

Core.EXT_SEC = "JKK_TRACK_MGR"

Core.EXT_KEYS = {
    HIDE_TCP     = "HIDE_TCP",
    HIDE_MCP     = "HIDE_MCP",
    HEARTBEAT    = "HEARTBEAT",
    FOCUS_REQ    = "FOCUS_REQ",
    TR_INACTIVE  = "P_EXT:JKK_INACTIVE",
    HAS_PRE_NAME = "P_EXT:JKK_HAS_PRE_NAME",
    PRE_NAME     = "P_EXT:JKK_PRE_NAME",
    PRE_MUTE     = "P_EXT:JKK_PRE_MUTE",
    PRE_TCP      = "P_EXT:JKK_PRE_TCP",
    PRE_MCP      = "P_EXT:JKK_PRE_MCP",
    PRE_FX       = "P_EXT:JKK_PRE_FX",
}

Core.TRACK_PROP = {
    NAME         = "P_NAME",
    NUMBER       = "IP_TRACKNUMBER",
    FOLDER_DEPTH = "I_FOLDERDEPTH",
    FOLDER_COMP  = "I_FOLDERCOMPACT",
    MUTE         = "B_MUTE",
    SOLO         = "I_SOLO",
    REC_ARM      = "I_RECARM",
    SHOW_TCP     = "B_SHOWINTCP",
    SHOW_MCP     = "B_SHOWINMIXER",
}

Core.FOLDER_STATE = {
    NORMAL    = 0,
    COLLAPSED = 2,
    IS_PARENT = 1,
}

local INACTIVE_PREFIX = "(inactive)"

local function FormatInactiveName(base_name)
    if base_name == nil or base_name == "" then
        return INACTIVE_PREFIX
    end
    return INACTIVE_PREFIX .. " " .. base_name
end

local function StripInactivePrefix(name)
    if not name or name == "" then return "" end
    local stripped = name:gsub("^%(inactive%)%s*", "")
    return stripped
end

function Core.GetHideFlags()
    local hide_tcp = RPR.HasExtState(Core.EXT_SEC, Core.EXT_KEYS.HIDE_TCP)
        and RPR.GetExtState(Core.EXT_SEC, Core.EXT_KEYS.HIDE_TCP) == "1" or false
    local hide_mcp = RPR.HasExtState(Core.EXT_SEC, Core.EXT_KEYS.HIDE_MCP)
        and RPR.GetExtState(Core.EXT_SEC, Core.EXT_KEYS.HIDE_MCP) == "1" or false
    return hide_tcp, hide_mcp
end

function Core.SetHideFlags(hide_tcp, hide_mcp)
    RPR.SetExtState(Core.EXT_SEC, Core.EXT_KEYS.HIDE_TCP, hide_tcp and "1" or "0", true)
    RPR.SetExtState(Core.EXT_SEC, Core.EXT_KEYS.HIDE_MCP, hide_mcp and "1" or "0", true)
end

function Core.IsTrackActive(tr)
    local _, state_str = RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.TR_INACTIVE, "", false)
    return state_str ~= "1"
end

function Core.AreAllTrackFXOnline(tr)
    local fx_count = RPR.TrackFX_GetCount(tr)
    if fx_count == 0 then return false end
    for fx = 0, fx_count - 1 do
        if RPR.TrackFX_GetOffline(tr, fx) then
            return false
        end
    end
    return true
end

function Core.GetStoredPreName(tr)
    local _, has_flag = RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.HAS_PRE_NAME, "", false)
    if has_flag == "1" then
        local _, saved_name = RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.PRE_NAME, "", false)
        return saved_name or ""
    end
    local _, cur_name = RPR.GetSetMediaTrackInfo_String(tr, Core.TRACK_PROP.NAME, "", false)
    local clean_name = StripInactivePrefix(cur_name)
    RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.HAS_PRE_NAME, "1", true)
    RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.PRE_NAME, clean_name, true)
    return clean_name
end

function Core.SavePreState(tr)
    local _, cur_name = RPR.GetSetMediaTrackInfo_String(tr, Core.TRACK_PROP.NAME, "", false)
    local clean_name = StripInactivePrefix(cur_name)
    RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.HAS_PRE_NAME, "1", true)
    RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.PRE_NAME, clean_name, true)

    RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.PRE_MUTE, tostring(RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.MUTE)), true)
    RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.PRE_TCP,  tostring(RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.SHOW_TCP)), true)
    RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.PRE_MCP,  tostring(RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.SHOW_MCP)), true)

    local fx_count = RPR.TrackFX_GetCount(tr)
    local fx_states = {}
    for fx = 0, fx_count - 1 do
        fx_states[#fx_states + 1] = RPR.TrackFX_GetOffline(tr, fx) and "1" or "0"
    end
    RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.PRE_FX, table.concat(fx_states, ","), true)
end

function Core.RestorePreState(tr)
    local _, has_name = RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.HAS_PRE_NAME, "", false)
    if has_name == "1" then
        local _, orig_name = RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.PRE_NAME, "", false)
        RPR.GetSetMediaTrackInfo_String(tr, Core.TRACK_PROP.NAME, orig_name or "", true)
    else
        local _, cur_name = RPR.GetSetMediaTrackInfo_String(tr, Core.TRACK_PROP.NAME, "", false)
        RPR.GetSetMediaTrackInfo_String(tr, Core.TRACK_PROP.NAME, StripInactivePrefix(cur_name), true)
    end
    RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.HAS_PRE_NAME, "", true)
    RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.PRE_NAME, "", true)

    local _, mute = RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.PRE_MUTE, "", false)
    if mute ~= "" then RPR.SetMediaTrackInfo_Value(tr, Core.TRACK_PROP.MUTE, tonumber(mute)) end

    local _, tcp = RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.PRE_TCP, "", false)
    if tcp ~= "" then RPR.SetMediaTrackInfo_Value(tr, Core.TRACK_PROP.SHOW_TCP, tonumber(tcp)) end

    local _, mcp = RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.PRE_MCP, "", false)
    if mcp ~= "" then RPR.SetMediaTrackInfo_Value(tr, Core.TRACK_PROP.SHOW_MCP, tonumber(mcp)) end

    local _, fx_str = RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.PRE_FX, "", false)
    if fx_str ~= "" then
        local fx_count = RPR.TrackFX_GetCount(tr)
        local idx = 0
        for state in string.gmatch(fx_str, "%d") do
            if idx < fx_count then
                RPR.TrackFX_SetOffline(tr, idx, state == "1")
            end
            idx = idx + 1
        end
    end
end

function Core.ApplyInactiveStateToTrack(tr, hide_tcp, hide_mcp)
    if hide_tcp == nil or hide_mcp == nil then
        hide_tcp, hide_mcp = Core.GetHideFlags()
    end

    -- 트랙 이름 앞에 (inactive) 유지 및 이름 수정 불가 잠금
    local base_name = Core.GetStoredPreName(tr)
    local expected_name = FormatInactiveName(base_name)
    local _, cur_name = RPR.GetSetMediaTrackInfo_String(tr, Core.TRACK_PROP.NAME, "", false)
    if cur_name ~= expected_name then
        RPR.GetSetMediaTrackInfo_String(tr, Core.TRACK_PROP.NAME, expected_name, true)
    end

    if RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.MUTE) == 0 then
        RPR.SetMediaTrackInfo_Value(tr, Core.TRACK_PROP.MUTE, 1)
    end
    if RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.SOLO) ~= 0 then
        RPR.SetMediaTrackInfo_Value(tr, Core.TRACK_PROP.SOLO, 0)
    end
    if RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.REC_ARM) ~= 0 then
        RPR.SetMediaTrackInfo_Value(tr, Core.TRACK_PROP.REC_ARM, 0)
    end

    local fx_count = RPR.TrackFX_GetCount(tr)
    for fx = 0, fx_count - 1 do
        if not RPR.TrackFX_GetOffline(tr, fx) then
            RPR.TrackFX_SetOffline(tr, fx, true)
        end
    end

    local want_tcp = hide_tcp and 0 or 1
    local want_mcp = hide_mcp and 0 or 1
    local changed_vis = false

    if RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.SHOW_TCP) ~= want_tcp then
        RPR.SetMediaTrackInfo_Value(tr, Core.TRACK_PROP.SHOW_TCP, want_tcp)
        changed_vis = true
    end
    if RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.SHOW_MCP) ~= want_mcp then
        RPR.SetMediaTrackInfo_Value(tr, Core.TRACK_PROP.SHOW_MCP, want_mcp)
        changed_vis = true
    end
    return changed_vis
end

function Core.EnforceInactive(hide_tcp, hide_mcp)
    if hide_tcp == nil or hide_mcp == nil then
        hide_tcp, hide_mcp = Core.GetHideFlags()
    end

    local num_tracks = RPR.CountTracks(0)
    local need_win_adjust = false
    for i = 0, num_tracks - 1 do
        local tr = RPR.GetTrack(0, i)
        if not Core.IsTrackActive(tr) then
            if Core.ApplyInactiveStateToTrack(tr, hide_tcp, hide_mcp) then
                need_win_adjust = true
            end
        end
    end
    if need_win_adjust then
        RPR.TrackList_AdjustWindows(false)
    end
end

function Core.SetTrackActiveState(tr, make_active, hide_tcp, hide_mcp)
    local currently_active = Core.IsTrackActive(tr)
    if not make_active and currently_active then
        Core.SavePreState(tr)
        RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.TR_INACTIVE, "1", true)
        local item_count = RPR.CountTrackMediaItems(tr)
        for j = 0, item_count - 1 do
            RPR.SetMediaItemSelected(RPR.GetTrackMediaItem(tr, j), false)
        end
        Core.ApplyInactiveStateToTrack(tr, hide_tcp, hide_mcp)
        if RPR.MarkProjectDirty then RPR.MarkProjectDirty(0) end
    elseif make_active and not currently_active then
        RPR.GetSetMediaTrackInfo_String(tr, Core.EXT_KEYS.TR_INACTIVE, "", true)
        Core.RestorePreState(tr)
        if RPR.MarkProjectDirty then RPR.MarkProjectDirty(0) end
    end
end

function Core.ToggleTrackAndChildrenActive(tr, make_active, hide_tcp, hide_mcp)
    Core.SetTrackActiveState(tr, make_active, hide_tcp, hide_mcp)
    if RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.FOLDER_DEPTH) == Core.FOLDER_STATE.IS_PARENT then
        local folder_idx = RPR.CSurf_TrackToID(tr, false)
        local num_tracks = RPR.CountTracks(0)
        local current_depth = 1
        for i = folder_idx, num_tracks - 1 do
            local child_tr = RPR.GetTrack(0, i)
            Core.SetTrackActiveState(child_tr, make_active, hide_tcp, hide_mcp)
            current_depth = current_depth + RPR.GetMediaTrackInfo_Value(child_tr, Core.TRACK_PROP.FOLDER_DEPTH)
            if current_depth <= 0 then break end
        end
    end
end

function Core.SetAllTracksActive(make_active, hide_tcp, hide_mcp)
    local num_tracks = RPR.CountTracks(0)
    for i = 0, num_tracks - 1 do
        local tr = RPR.GetTrack(0, i)
        Core.SetTrackActiveState(tr, make_active, hide_tcp, hide_mcp)
    end
end

function Core.SetSelectedTracksActive(make_active, undo_label)
    local sel_count = RPR.CountSelectedTracks(0)
    if sel_count == 0 then return end

    local hide_tcp, hide_mcp = Core.GetHideFlags()
    RPR.Undo_BeginBlock()
    RPR.PreventUIRefresh(1)
    for i = 0, sel_count - 1 do
        local tr = RPR.GetSelectedTrack(0, i)
        if tr then
            Core.ToggleTrackAndChildrenActive(tr, make_active, hide_tcp, hide_mcp)
        end
    end
    RPR.TrackList_AdjustWindows(false)
    RPR.UpdateArrange()
    RPR.PreventUIRefresh(-1)
    RPR.Undo_EndBlock(undo_label or (make_active and "Activate Selected Tracks" or "Deactivate Selected Tracks"), -1)
end

return Core