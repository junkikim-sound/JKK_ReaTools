--========================================================
-- @title JKK_TrackManager_Core
-- @author Junki Kim
-- @noindex
--========================================================

local RPR = reaper
local Undo = dofile(((debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or "") .. "JKK_UndoLabels.lua")
local Core = {}

Core.EXT_SEC = "JKK_TRACK_MGR"

Core.EXT_KEYS = {
    HIDE_TCP     = "HIDE_TCP",
    HIDE_MCP     = "HIDE_MCP",
    VIEW_FILTER  = "VIEW_FILTER",
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

-- Display-only filtering: 0 = All Tracks, 1 = Inactive, 2 = Active.
-- Never change actual track activation when changing the view.
Core.VIEW_FILTERS = {"All Tracks", "Inactive Tracks", "Active Tracks"}

function Core.GetViewFilter()
    local value = tonumber(RPR.GetExtState(Core.EXT_SEC, Core.EXT_KEYS.VIEW_FILTER)) or 0
    if value < 0 or value >= #Core.VIEW_FILTERS or value % 1 ~= 0 then return 0 end
    return value
end

function Core.SetViewFilter(value)
    value = tonumber(value) or 0
    value = math.floor(value) % #Core.VIEW_FILTERS
    RPR.SetExtState(Core.EXT_SEC, Core.EXT_KEYS.VIEW_FILTER, tostring(value), true)
    return value
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
    RPR.Undo_EndBlock(undo_label or (make_active and Undo.Label("track_manager.activate_selected_tracks") or Undo.Label("track_manager.deactivate_selected_tracks")), -1)
end


-- Toggle all currently selected tracks (folders include their descendants).
-- When any selected track is active we deactivate the selection;
-- otherwise we restore the selection together.
function Core.ToggleSelectedTracksActive()
    local count = RPR.CountSelectedTracks(0)
    if count < 1 then return false end
    local any_active = false
    for i = 0, count - 1 do
        local tr = RPR.GetSelectedTrack(0, i)
        if tr and Core.IsTrackActive(tr) then
            any_active = true
            break
        end
    end
    Core.SetSelectedTracksActive(not any_active, Undo.Label("track_manager.toggle_selected"))
    return true
end

local function GetNameForSorting(track)
    local _, name = RPR.GetSetMediaTrackInfo_String(track, Core.TRACK_PROP.NAME, "", false)
    name = StripInactivePrefix(name or "")
    return name:lower()
end

-- Natural A-Z ordering: digit runs are compared numerically without converting
-- them to Lua numbers (so long track numbers remain precise).
-- Non-numeric characters use case-insensitive lexical ordering.
local function NaturalLess(a, b)
    local ia, ib = 1, 1
    while ia <= #a and ib <= #b do
        local ca, cb = a:sub(ia, ia), b:sub(ib, ib)
        if ca:match("%d") and cb:match("%d") then
            local ra = a:sub(ia):match("^(%d+)")
            local rb = b:sub(ib):match("^(%d+)")
            local na = ra:gsub("^0+", "")
            local nb = rb:gsub("^0+", "")
            if na == "" then na = "0" end
            if nb == "" then nb = "0" end
            if #na ~= #nb then return #na < #nb end
            if na ~= nb then return na < nb end
            ia, ib = ia + #ra, ib + #rb
        else
            if ca ~= cb then return ca < cb end
            ia, ib = ia + 1, ib + 1
        end
    end
    return ia > #a and ib <= #b
end

local function TrackIsDescendantOf(track, ancestor)
    local parent = RPR.GetParentTrack(track)
    while parent do
        if parent == ancestor then return true end
        parent = RPR.GetParentTrack(parent)
    end
    return false
end

local function GatherSiblingUnits(parent)
    local total = RPR.CountTracks(0)
    local units = {}
    for i = 0, total - 1 do
        local track = RPR.GetTrack(0, i)
        if RPR.GetParentTrack(track) == parent then
            local is_folder = RPR.GetMediaTrackInfo_Value(track, Core.TRACK_PROP.FOLDER_DEPTH) == 1
            local members = {track}
            if is_folder then
                for j = i + 1, total - 1 do
                    local child = RPR.GetTrack(0, j)
                    if not TrackIsDescendantOf(child, track) then break end
                    members[#members+1] = child
                end
            end
            units[#units+1] = {
                track = track,
                members = members,
                is_folder = is_folder,
                key = GetNameForSorting(track),
                index = i,
            }
        end
    end
    return units
end

-- Sort every direct child of the selected track's parent, whether an
-- ordinary track or a folder. A folder and all descendants move as ONE unit.
-- Only one level is sorted (never recurse into child folders).
-- When multiple tracks are selected, the first selected track in project
-- order supplies the parent/sort scope; preserve every track selection.
function Core.SortSelectedTrackSiblingsAZ()
    if not RPR.ReorderSelectedTracks then
        return false, "This REAPER version does not support ReorderSelectedTracks."
    end

    local selected = {}
    local parent = nil
    for i = 0, RPR.CountSelectedTracks(0) - 1 do
        local tr = RPR.GetSelectedTrack(0, i)
        if tr then
            selected[#selected + 1] = tr
            if #selected == 1 then parent = RPR.GetParentTrack(tr) end
        end
    end
    if #selected == 0 then return false, "Select a track to sort its siblings." end

    local units = GatherSiblingUnits(parent)
    if #units < 2 then return false, "Only one track exists at this level." end

    local sorted = {}
    for i, unit in ipairs(units) do sorted[i] = unit end
    table.sort(sorted, function(a, b)
        if a.key == b.key then return a.index < b.index end
        -- NaturalLess intentionally treats 1 and 01 as equivalent.
        if NaturalLess(a.key, b.key) then return true end
        if NaturalLess(b.key, a.key) then return false end
        return a.index < b.index
    end)
    local changed = false
    for i, unit in ipairs(units) do
        if sorted[i] ~= unit then changed = true; break end
    end
    if not changed then return false, "Tracks are already sorted A-Z at this level." end

    local groups = {{
        parent = parent,
        original = units,
        target = sorted,
        start = units[1].index,
        depth = parent and RPR.GetTrackDepth(parent) + 1 or 0,
    }}

    -- Capture all original folder boundaries before any reordering. The track
    -- at the end of a parent group closes the parent folder (possibly several
    -- ancestor folders). This closure must follow the *new* last sibling.
    local total = RPR.CountTracks(0)
    local saved_order, target_order, depth_values = {}, {}, {}
    for i = 0, total - 1 do
        local tr = RPR.GetTrack(0, i)
        saved_order[#saved_order+1] = tr
        target_order[#target_order+1] = tr
        depth_values[tr] = RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.FOLDER_DEPTH)
    end

    -- Disjoint groups may be nested. Build the expected final pointer order by
    -- moving each group's original complete sibling span in memory.
    table.sort(groups, function(a,b)
        if a.depth == b.depth then return a.start > b.start end
        return a.depth > b.depth
    end)
    for _, group in ipairs(groups) do
        local flat = {}
        for _, unit in ipairs(group.target) do
            for _, tr in ipairs(unit.members) do flat[#flat+1] = tr end
        end
        local initial_flat = {}
        for _, unit in ipairs(group.original) do
            for _, tr in ipairs(unit.members) do initial_flat[#initial_flat+1] = tr end
        end
        local first_pos
        for j, tr in ipairs(target_order) do
            if tr == initial_flat[1] then first_pos = j; break end
        end
        if not first_pos then return false, "Unable to locate track group." end
        for j=1,#flat do target_order[first_pos+j-1] = flat[j] end

        if group.parent then
            local old_last_unit = group.original[#group.original]
            local new_last_unit = group.target[#group.target]
            if old_last_unit ~= new_last_unit then
                local net_depth = 0
                for _, tr in ipairs(old_last_unit.members) do
                    net_depth = net_depth + depth_values[tr]
                end
                local outer_closures = math.max(0, -net_depth)
                if outer_closures > 0 then
                    local old_tail = old_last_unit.members[#old_last_unit.members]
                    local new_tail = new_last_unit.members[#new_last_unit.members]
                    depth_values[old_tail] = depth_values[old_tail] + outer_closures
                    depth_values[new_tail] = depth_values[new_tail] - outer_closures
                end
            end
        end
    end

    local function RestoreSelection()
        for i=0,RPR.CountTracks(0)-1 do
            RPR.SetTrackSelected(RPR.GetTrack(0,i),false)
        end
        for _, tr in ipairs(selected) do
            if RPR.ValidatePtr2(0,tr,"MediaTrack*") then
                RPR.SetTrackSelected(tr,true)
            end
        end
    end

    RPR.Undo_BeginBlock()
    RPR.PreventUIRefresh(1)
    local ok, err = pcall(function()
        for _, group in ipairs(groups) do
            local first = group.original[1].track
            -- Move groups in reverse order to the same anchor position.
            -- This preserves the internal track order of every subtree.
            local anchor_idx = math.floor(RPR.GetMediaTrackInfo_Value(first, "IP_TRACKNUMBER")) - 1
            for j=#group.target,1,-1 do
                for i=0,RPR.CountTracks(0)-1 do
                    RPR.SetTrackSelected(RPR.GetTrack(0,i),false)
                end
                for _, tr in ipairs(group.target[j].members) do RPR.SetTrackSelected(tr,true) end
                if not RPR.ReorderSelectedTracks(anchor_idx, 0) then
                    error("REAPER could not move a track group.")
                end
            end
        end
        for i, tr in ipairs(target_order) do
            if RPR.GetTrack(0, i-1) ~= tr then
                error("Track order validation failed. No changes will be kept.")
            end
        end
        -- Reapply the exact original folder-depth values with closing markers
        -- transferred to the new final sibling when necessary.
        for _, tr in ipairs(saved_order) do
            RPR.SetMediaTrackInfo_Value(tr, Core.TRACK_PROP.FOLDER_DEPTH, depth_values[tr])
        end
        RestoreSelection()
        RPR.TrackList_AdjustWindows(false)
        RPR.UpdateArrange()
    end)
    RPR.PreventUIRefresh(-1)
    RPR.Undo_EndBlock(Undo.Label("track_manager.jkk_sort_sibling_tracks_a_z"), -1)
    if not ok then
        RPR.Undo_DoUndo2(0)
        return false, tostring(err)
    end
    return true, string.format("Sorted %d sibling tracks A-Z.", #units)
end

-- Backward-compatible alias for older scripts calling the folder-only API.
Core.SortSelectedFolderSiblingsAZ = Core.SortSelectedTrackSiblingsAZ

return Core
