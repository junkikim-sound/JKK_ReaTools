--========================================================
-- @title JKK_ReaTools_NEW_RenamerLite
-- @author Junki Kim
-- @noindex
--========================================================

local reaper = reaper
local M = {
    status_info = {
        mode = "None",
        total_count = 0,
        rename_count = 0,
        top_level_only = false,
    }
}

local function S(v) return v * (JKK_UI_SCALE or 1) end

-- JKK_ReaTools가 먼저 로드한 SelectionManager 참조 (단독 로드 시 폴백 포함)
local script_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local sel_path = reaper.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_SelectionManager.lua"
if not reaper.file_exists(sel_path) then
    sel_path = script_dir .. "JKK_SelectionManager.lua"
end
local sel_mgr = _G.JKK_SelectionManager or (reaper.file_exists(sel_path) and dofile(sel_path))

local ext_section = "JKK_SmartBatchRenamer"
local use_number = reaper.GetExtState(ext_section, "use_number") == "1"
local top_level_only = reaper.GetExtState(ext_section, "top_level_only") == "1"
local number_start = tonumber(reaper.GetExtState(ext_section, "number_start")) or 1
local number_start_text = tostring(number_start)

local input_buf = ""
local last_target_signature = nil
local last_mode = nil
local was_active = false
local input_was_focused = false
local pending_default_name = nil

local function SaveSettings()
    reaper.SetExtState(ext_section, "use_number", use_number and "1" or "0", true)
    reaper.SetExtState(ext_section, "top_level_only", top_level_only and "1" or "0", true)
    reaper.SetExtState(ext_section, "number_start", tostring(number_start), true)
end

-- 스탠드얼론 JKK_Renamer와 실시간 상태 동기화
local function SyncSharedSettings(number_input_focused)
    local ext_num = reaper.GetExtState(ext_section, "use_number") == "1"
    local ext_top = reaper.GetExtState(ext_section, "top_level_only") == "1"
    local ext_start_raw = reaper.GetExtState(ext_section, "number_start")
    local ext_start = tonumber(ext_start_raw)

    if ext_num ~= use_number then
        use_number = ext_num
    end
    if ext_top ~= top_level_only then
        top_level_only = ext_top
    end
    if ext_start and ext_start ~= number_start and not number_input_focused then
        number_start = ext_start
        number_start_text = tostring(number_start)
    end
end

local function GetItemName(item)
    local take = item and reaper.GetActiveTake(item)
    if not take then return "" end
    local _, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    if (not name or name == "") and reaper.GetTakeName then
        name = reaper.GetTakeName(take)
    end
    return name or ""
end

local function GetTargets(mode, active)
    if not active or not sel_mgr then return {}, 0 end

    local raw_targets = sel_mgr.GetTargets()
    local total_count = #raw_targets
    if not top_level_only then return raw_targets, total_count end

    if mode == "Track" or mode == "Item" then
        local filtered = {}
        local selected_tracks = {}
        for _, target in ipairs(raw_targets) do
            if target.track then selected_tracks[target.track] = true end
        end
        for _, target in ipairs(raw_targets) do
            local parent = target.track and reaper.GetParentTrack(target.track)
            local has_selected_parent = false
            while parent do
                if selected_tracks[parent] then
                    has_selected_parent = true
                    break
                end
                parent = reaper.GetParentTrack(parent)
            end
            if not has_selected_parent then
                filtered[#filtered + 1] = target
            end
        end
        return filtered, total_count
    end

    return raw_targets, total_count
end

local function BuildHierarchyIndices(mode, targets)
    local indices = {}
    if mode == "Track" then
        local selected_tracks = {}
        for _, target in ipairs(targets) do selected_tracks[target.track] = true end

        local has_parent_child_relation = false
        for _, target in ipairs(targets) do
            local parent = reaper.GetParentTrack(target.track)
            while parent do
                if selected_tracks[parent] then
                    has_parent_child_relation = true
                    break
                end
                parent = reaper.GetParentTrack(parent)
            end
            if has_parent_child_relation then break end
        end

        if not has_parent_child_relation then
            for i = 1, #targets do
                indices[i] = string.format("%02d", (number_start - 1) + i)
            end
            return indices
        end

        local track_indices, child_counters = {}, {}
        local root_counter = number_start - 1
        for i, target in ipairs(targets) do
            local parent = reaper.GetParentTrack(target.track)
            local selected_parent = nil
            while parent do
                if selected_tracks[parent] then
                    selected_parent = parent
                    break
                end
                parent = reaper.GetParentTrack(parent)
            end
            if not selected_parent then
                root_counter = root_counter + 1
                local value = string.format("%02d", root_counter)
                track_indices[target.track] = value
                indices[i] = value
            else
                local parent_index = track_indices[selected_parent] or string.format("%02d", number_start)
                child_counters[selected_parent] = (child_counters[selected_parent] or 0) + 1
                local value = parent_index .. "_" .. string.format("%02d", child_counters[selected_parent])
                track_indices[target.track] = value
                indices[i] = value
            end
        end
    elseif mode == "Item" then
        local selected_tracks = {}
        for _, target in ipairs(targets) do selected_tracks[target.track] = true end

        local has_parent_child_relation = false
        for _, target in ipairs(targets) do
            local parent = reaper.GetParentTrack(target.track)
            while parent do
                if selected_tracks[parent] then
                    has_parent_child_relation = true
                    break
                end
                parent = reaper.GetParentTrack(parent)
            end
            if has_parent_child_relation then break end
        end

        if not has_parent_child_relation then
            for i = 1, #targets do
                indices[i] = string.format("%02d", (number_start - 1) + i)
            end
            return indices
        end

        local track_base_indices, child_item_counters = {}, {}
        local top_item_counter = number_start - 1
        local top_track_counter = number_start - 1
        for i, target in ipairs(targets) do
            local track = target.track
            local parent = reaper.GetParentTrack(track)
            local selected_parent = nil
            while parent do
                if selected_tracks[parent] then
                    selected_parent = parent
                    break
                end
                parent = reaper.GetParentTrack(parent)
            end

            if not selected_parent then
                top_item_counter = top_item_counter + 1
                local value = string.format("%02d", top_item_counter)
                if not track_base_indices[track] then track_base_indices[track] = value end
                indices[i] = value
            else
                local parent_index = track_base_indices[selected_parent]
                if not parent_index then
                    top_track_counter = top_track_counter + 1
                    parent_index = string.format("%02d", top_track_counter)
                    track_base_indices[selected_parent] = parent_index
                end
                child_item_counters[track] = (child_item_counters[track] or 0) + 1
                local value = parent_index .. "_" .. string.format("%02d", child_item_counters[track])
                track_base_indices[track] = value
                indices[i] = value
            end
        end
    else
        for i = 1, #targets do
            indices[i] = string.format("%02d", (number_start - 1) + i)
        end
    end
    return indices
end

local function GetTargetSignature(mode, targets)
    local parts = { mode or "None" }
    for _, target in ipairs(targets) do
        local pointer = target.item or target.track or target.pm or tostring(target.index or "")
        parts[#parts + 1] = tostring(pointer) .. ":" .. tostring(target.original_name or "")
    end
    return table.concat(parts, "|")
end

local function SetTargetName(target, new_name)
    if target.type == "Item" then
        local take = reaper.GetActiveTake(target.item)
        if take then reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", new_name, true) end
    elseif target.type == "Track" then
        reaper.GetSetMediaTrackInfo_String(target.track, "P_NAME", new_name, true)
    elseif target.type == "Region" or target.type == "Marker" then
        if target.pm and reaper.GetSetRegionOrMarkerInfo_String then
            reaper.GetSetRegionOrMarkerInfo_String(0, target.pm, "P_NAME", new_name, true)
        else
            reaper.SetProjectMarker3(0, target.index, target.is_region, target.pos,
                target.rgnend, new_name, target.color or 0)
        end
    end
end

local function Plain(text)
    return (tostring(text or ""):gsub("%%", "%%%%"))
end

local function EvaluateName(pattern, target, index, hierarchy_indices)
    local out = pattern
    if out == "" then return "" end

    local project_name = reaper.GetProjectName(0, ""):gsub("%.%w+$", "")
    out = out:gsub("%$project", Plain(project_name))
    out = out:gsub("%$datetime", os.date("%Y-%m-%d %H_%M_%S"))
    out = out:gsub("%$date", os.date("%Y-%m-%d"))
    out = out:gsub("%$time", os.date("%H_%M_%S"))
    out = out:gsub("%$year2", os.date("%y"))
    out = out:gsub("%$year", os.date("%Y"))
    out = out:gsub("%$monthname", os.date("%B"))
    out = out:gsub("%$month", os.date("%m"))
    out = out:gsub("%$dayname", os.date("%A"))
    out = out:gsub("%$day", os.date("%d"))
    out = out:gsub("%$hour12", os.date("%I"))
    out = out:gsub("%$hour", os.date("%H"))
    out = out:gsub("%$ampm", os.date("%p"))
    out = out:gsub("%$minute", os.date("%M"))
    out = out:gsub("%$second", os.date("%S"))
    out = out:gsub("%$localtime", os.date("%p %I:%M, %B %d %Y"))

    if target.type == "Item" then
        local _, track_name = reaper.GetTrackName(target.track)
        out = out:gsub("%$track", Plain(track_name))
        out = out:gsub("%$item", Plain(target.original_name))
        out = out:gsub("%$region", "")
        out = out:gsub("%$marker", "")
    elseif target.type == "Track" then
        out = out:gsub("%$track", Plain(target.original_name))
        out = out:gsub("%$item", "")
        out = out:gsub("%$region", "")
        out = out:gsub("%$marker", "")
    elseif target.type == "Region" or target.type == "Marker" then
        out = out:gsub("%$region", Plain(target.original_name))
        out = out:gsub("%$marker", Plain(target.original_name))
        out = out:gsub("%$track", "")
        out = out:gsub("%$item", "")
    end

    if out:find("%$filenumber%[%d+%]") then
        local number = hierarchy_indices and hierarchy_indices[index]
            or string.format("%02d", (number_start - 1) + index)
        out = out:gsub("%$filenumber%[%d+%]", number)
    end

    if out:find("%$uniqueid%[[%wN]+%]") then
        out = out:gsub("%$uniqueid%[[%wN]+%]", "ID" .. tostring(math.random(1000, 9999)))
    end

    if use_number and not pattern:find("%$filenumber%[%d+%]") then
        local number = hierarchy_indices and hierarchy_indices[index]
            or string.format("%02d", (number_start - 1) + index)
        out = out .. "_" .. number
    end
    return out
end

local function CreateRegionsFromItems(per_item, base_name)
    local items = sel_mgr and sel_mgr.GetSelectedItems() or {}
    if #items == 0 then return end

    local spans = {}
    for _, item in ipairs(items) do
        local start_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local end_pos = start_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        spans[#spans + 1] = { start_pos = start_pos, end_pos = end_pos, name = GetItemName(item) }
    end
    table.sort(spans, function(a, b) return a.start_pos < b.start_pos end)

    local regions = {}
    if per_item then
        regions = spans
    else
        for _, span in ipairs(spans) do
            local last = regions[#regions]
            if last and span.start_pos <= last.end_pos then
                last.end_pos = math.max(last.end_pos, span.end_pos)
            else
                regions[#regions + 1] = { start_pos = span.start_pos, end_pos = span.end_pos, first_name = span.name }
            end
        end
        for i, region in ipairs(regions) do
            if base_name and base_name ~= "" then
                region.name = (#regions > 1)
                    and string.format("%s_%02d", base_name, (number_start - 1) + i) or base_name
            else
                region.name = region.first_name
            end
        end
    end

    reaper.Undo_BeginBlock()
    for _, region in ipairs(regions) do
        reaper.AddProjectMarker(0, true, region.start_pos, region.end_pos, region.name or "", -1)
    end
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Create Regions from Items", -1)
end

local function ApplyRename(mode, targets, name_pattern)
    if #targets == 0 or name_pattern == "" then return false end

    local indices = nil
    if use_number and not top_level_only then
        indices = BuildHierarchyIndices(mode, targets)
    end

    reaper.Undo_BeginBlock()
    for i, target in ipairs(targets) do
        local new_name = EvaluateName(name_pattern, target, i, indices)
        SetTargetName(target, new_name)
    end
    reaper.Undo_EndBlock("JKK ReaTools - Rename", -1)
    reaper.UpdateArrange()
    return true
end

local number_input_focused = false

local function DrawRenamerLite(ctx, mode, active)
    SyncSharedSettings(number_input_focused)

    local targets, total_count = GetTargets(mode, active)
    M.status_info.mode = mode or "None"
    M.status_info.total_count = total_count
    M.status_info.rename_count = #targets
    M.status_info.top_level_only = top_level_only

    local target_signature = GetTargetSignature(mode, targets)
    local first_name = (#targets > 0) and (targets[1].original_name or "") or ""

    local is_mouse_down = sel_mgr and sel_mgr.IsMouseDown() or false

    if active and #targets > 0 and not is_mouse_down then
        if not was_active or target_signature ~= last_target_signature or mode ~= last_mode then
            if input_was_focused then
                pending_default_name = first_name
            else
                input_buf = first_name
                pending_default_name = nil
            end
        elseif pending_default_name and not input_was_focused then
            input_buf = pending_default_name
            pending_default_name = nil
        end
    end

    local available_width = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    local row_start_x = reaper.ImGui_GetCursorPosX(ctx)
    local apply_width = S(100)
    local gap = S(6)
    local input_width = math.max(1, available_width - apply_width - gap)

    if JKK_Theme then JKK_Theme.PushFont(ctx, JKK_UI_SCALE or 1.0, "topbar") end
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), S(8), S(4.5))
    local input_height = reaper.ImGui_GetFrameHeight(ctx)

    reaper.ImGui_SetNextItemWidth(ctx, input_width)
    local hint = (#targets > 0) and first_name or "Select an item, track, or timeline target"
    local changed, new_buf = reaper.ImGui_InputTextWithHint(ctx, "##WorkspaceRenameInput", hint, input_buf)
    if changed then input_buf = new_buf end
    local input_focused = reaper.ImGui_IsItemFocused(ctx)

    reaper.ImGui_SameLine(ctx, 0, gap)
    reaper.ImGui_BeginDisabled(ctx, not active or #targets == 0)
    if JKK_Theme then JKK_Theme.PushButton(ctx, "confirm") end
    local apply_clicked = reaper.ImGui_Button(ctx, "Apply", apply_width, input_height)
    if JKK_Theme then JKK_Theme.PopButton(ctx) end

    local enter_pressed = input_focused and (
        reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter())
        or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter())
    )
    if (apply_clicked or enter_pressed) and #targets > 0 then
        ApplyRename(mode, targets, input_buf)
    end
    reaper.ImGui_EndDisabled(ctx)

    reaper.ImGui_PopStyleVar(ctx, 1)
    if JKK_Theme then JKK_Theme.PopFont(ctx) end

    local options_row_y = reaper.ImGui_GetCursorPosY(ctx)
    local checkbox_height = reaper.ImGui_GetFrameHeight(ctx)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), S(8), 0)

    local number_changed, new_number = reaper.ImGui_Checkbox(ctx, "Number (_nn)", use_number)
    if number_changed then
        use_number = new_number
        SaveSettings()
    end

    number_input_focused = false
    if use_number then
        reaper.ImGui_SameLine(ctx, 0, S(4))
        reaper.ImGui_SetNextItemWidth(ctx, S(64))
        local start_changed, new_start = reaper.ImGui_InputText(
            ctx, "##RenamerLiteNumberStart", number_start_text
        )
        number_input_focused = reaper.ImGui_IsItemFocused(ctx)
        if start_changed then
            number_start_text = new_start
            local parsed = tonumber(number_start_text)
            if parsed and parsed >= 1 then
                number_start = math.floor(parsed)
                SaveSettings()
            end
        end
        if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
            local parsed = tonumber(number_start_text)
            if parsed and parsed >= 1 then
                number_start = math.floor(parsed)
                number_start_text = tostring(number_start)
                SaveSettings()
            else
                number_start_text = tostring(number_start)
            end
        end
    end

    reaper.ImGui_SameLine(ctx, 0, S(8))
    local top_changed, new_top = reaper.ImGui_Checkbox(ctx, "Top-Level Only", top_level_only)
    if top_changed then
        top_level_only = new_top
        SaveSettings()
    end

    local selected_items = sel_mgr and sel_mgr.GetSelectedItems() or {}
    local item_ready = active and mode == "Item" and #selected_items > 0
    reaper.ImGui_SameLine(ctx, 0, S(8))
    reaper.ImGui_BeginDisabled(ctx, not item_ready)
    local region_btn_width = S(92)
    local region_clicked = reaper.ImGui_Button(ctx, "Create Regions##Inline", region_btn_width + 25, checkbox_height)
    reaper.ImGui_EndDisabled(ctx)
    if region_clicked then
        if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift()) then
            CreateRegionsFromItems(true)
        else
            CreateRegionsFromItems(false, input_buf)
        end
    end
    if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled()) then
        reaper.ImGui_SetTooltip(ctx, "Click: one region around each group of overlapping items (longest extent),\nnamed from the text field\nShift+Click: one region per item, named after the item")
    end

    local open_button_width = S(100)
    local open_button_height = S(22)
    reaper.ImGui_SameLine(ctx, 0, 0)
    reaper.ImGui_SetCursorPosX(ctx, row_start_x + math.max(0, available_width - open_button_width))
    reaper.ImGui_SetCursorPosY(ctx, options_row_y + math.max(0, (checkbox_height - open_button_height) * 0.5))

    if JKK_Theme then JKK_Theme.PushButton(ctx, "primary") end
    if reaper.ImGui_Button(ctx, "Renamer", open_button_width, open_button_height) then
        local command_id = reaper.NamedCommandLookup("_RS2343473a341aa2705a7b16c73d17d2fba2912208")
        if command_id and command_id ~= 0 then
            reaper.Main_OnCommand(command_id, 0)
        else
            reaper.ShowMessageBox("JKK_Renamer command could not be found. Check the ReaScript action ID.", "JKK_ReaTools", 0)
        end
    end
    if JKK_Theme then JKK_Theme.PopButton(ctx) end
    reaper.ImGui_PopStyleVar(ctx, 1)

    input_was_focused = input_focused
    was_active = active and #targets > 0
    if not is_mouse_down then
        last_target_signature = target_signature
        last_mode = mode
    end
end

M.JKK_RenamerLite_Draw = DrawRenamerLite
return M