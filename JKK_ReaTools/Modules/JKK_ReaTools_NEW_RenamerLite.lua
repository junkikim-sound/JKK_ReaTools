--========================================================
-- @title JKK_ReaTools_NEW_RenamerLite
-- @author Junki Kim
-- @noindex
--========================================================

local reaper = reaper

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

local function GetItemName(item)
    local take = item and reaper.GetActiveTake(item)
    if not take then return "" end
    local _, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    if (not name or name == "") and reaper.GetTakeName then
        name = reaper.GetTakeName(take)
    end
    return name or ""
end

local function GetTrackName(track)
    if not track then return "" end
    local _, name = reaper.GetTrackName(track)
    return name or ""
end

local function GetTargets(mode, active)
    local targets = {}
    if not active then return targets end

    if mode == "Item" then
        for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            if item then
                local track = reaper.GetMediaItem_Track(item)
                targets[#targets + 1] = {
                    type = "Item", item = item, track = track,
                    original_name = GetItemName(item)
                }
            end
        end
    elseif mode == "Track" then
        for i = 0, reaper.CountSelectedTracks(0) - 1 do
            local track = reaper.GetSelectedTrack(0, i)
            if track then
                targets[#targets + 1] = {
                    type = "Track", track = track,
                    original_name = GetTrackName(track)
                }
            end
        end
    elseif mode == "Region/Marker" then
        local selected_regions, selected_markers = {}, {}
        if reaper.GetNumRegionsOrMarkers and reaper.GetRegionOrMarker
            and reaper.GetRegionOrMarkerInfo_Value then
            local marker_count, region_count = reaper.GetNumRegionsOrMarkers(0)
            for idx = 0, (marker_count or 0) + (region_count or 0) - 1 do
                local pm = reaper.GetRegionOrMarker(0, idx, "")
                if pm and reaper.GetRegionOrMarkerInfo_Value(0, pm, "B_UISEL") > 0 then
                    local is_region = reaper.GetRegionOrMarkerInfo_Value(0, pm, "B_ISREGION") == 1
                    local pos = reaper.GetRegionOrMarkerInfo_Value(0, pm, "D_STARTPOS")
                    local region_end = reaper.GetRegionOrMarkerInfo_Value(0, pm, "D_ENDPOS")
                    local number = math.floor(reaper.GetRegionOrMarkerInfo_Value(0, pm, "I_NUMBER") + 0.5)
                    local color = math.floor(reaper.GetRegionOrMarkerInfo_Value(0, pm, "I_CUSTOMCOLOR") + 0.5)
                    local _, name = reaper.GetSetRegionOrMarkerInfo_String(0, pm, "P_NAME", "", false)
                    local target = {
                        type = is_region and "Region" or "Marker", pm = pm,
                        index = number, is_region = is_region, pos = pos,
                        rgnend = is_region and region_end or 0,
                        color = color, original_name = name or ""
                    }
                    if is_region then
                        selected_regions[#selected_regions + 1] = target
                    else
                        selected_markers[#selected_markers + 1] = target
                    end
                end
            end
        end

        for _, target in ipairs(selected_regions) do targets[#targets + 1] = target end
        for _, target in ipairs(selected_markers) do targets[#targets + 1] = target end

        -- If no region/marker is explicitly selected, use objects intersecting
        -- the current time selection, matching the full JKK_Renamer behavior.
        if #targets == 0 then
            local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
            if ts_end > ts_start then
                local idx = 0
                while true do
                    local retval, is_region, pos, region_end, name, number, color = reaper.EnumProjectMarkers3(0, idx)
                    if retval == 0 then break end
                    if is_region then
                        if pos < ts_end and region_end > ts_start then
                            targets[#targets + 1] = {
                                type = "Region", index = number, is_region = true,
                                pos = pos, rgnend = region_end, color = color,
                                original_name = name or ""
                            }
                        end
                    elseif pos >= ts_start and pos <= ts_end then
                        targets[#targets + 1] = {
                            type = "Marker", index = number, is_region = false,
                            pos = pos, rgnend = 0, color = color,
                            original_name = name or ""
                        }
                    end
                    idx = idx + 1
                end
            end
        end
    end

    if not top_level_only then return targets end

    local filtered = {}
    if mode == "Track" then
        local selected_tracks = {}
        for _, target in ipairs(targets) do selected_tracks[target.track] = true end
        for _, target in ipairs(targets) do
            local parent = reaper.GetParentTrack(target.track)
            local has_selected_parent = false
            while parent do
                if selected_tracks[parent] then
                    has_selected_parent = true
                    break
                end
                parent = reaper.GetParentTrack(parent)
            end
            if not has_selected_parent then filtered[#filtered + 1] = target end
        end
        return filtered
    elseif mode == "Item" then
        local selected_tracks = {}
        for _, target in ipairs(targets) do selected_tracks[target.track] = true end
        for _, target in ipairs(targets) do
            local parent = reaper.GetParentTrack(target.track)
            local has_selected_parent = false
            while parent do
                if selected_tracks[parent] then
                    has_selected_parent = true
                    break
                end
                parent = reaper.GetParentTrack(parent)
            end
            if not has_selected_parent then filtered[#filtered + 1] = target end
        end
        return filtered
    end

    return targets
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

local function EvaluateName(pattern, target, index, hierarchy_indices)
    local out = pattern
    if out == "" then return "" end

    local project_name = reaper.GetProjectName(0, ""):gsub("%.%w+$", "")
    out = out:gsub("%$project", project_name)
    out = out:gsub("%$date", os.date("%Y-%m-%d"))
    out = out:gsub("%$time", os.date("%H_%M_%S"))
    out = out:gsub("%$datetime", os.date("%Y-%m-%d %H_%M_%S"))
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
        out = out:gsub("%$track", track_name or "")
        out = out:gsub("%$item", target.original_name or "")
        out = out:gsub("%$region", "")
        out = out:gsub("%$marker", "")
    elseif target.type == "Track" then
        out = out:gsub("%$track", target.original_name or "")
        out = out:gsub("%$item", "")
        out = out:gsub("%$region", "")
        out = out:gsub("%$marker", "")
    elseif target.type == "Region" or target.type == "Marker" then
        out = out:gsub("%$region", target.original_name or "")
        out = out:gsub("%$marker", target.original_name or "")
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

local function DrawRenamerLite(ctx, mode, active, input_font, properties_button_width)
    local targets = GetTargets(mode, active)
    local target_signature = GetTargetSignature(mode, targets)
    local first_name = (#targets > 0) and (targets[1].original_name or "") or ""

    if active and #targets > 0 then
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
    -- Capture the left edge before drawing the first row so the lower button
    -- can share the exact same right boundary as Apply.
    local row_start_x = reaper.ImGui_GetCursorPosX(ctx)
    local apply_width = 82
    local gap = 6
    local input_width = math.max(1, available_width - apply_width - gap)

    -- Use the font attached by the main script before the first UI frame.
    -- This keeps font atlas changes out of the active ImGui draw cycle.
    if input_font then reaper.ImGui_PushFont(ctx, input_font, 13) end
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 8, 3)
    local input_height = reaper.ImGui_GetFrameHeight(ctx)

    reaper.ImGui_BeginDisabled(ctx, not active or #targets == 0)
    reaper.ImGui_SetNextItemWidth(ctx, input_width)
    local hint = (#targets > 0) and first_name or "Select an item, track, or timeline target"
    local changed, new_buf = reaper.ImGui_InputTextWithHint(ctx, "##WorkspaceRenameInput", hint, input_buf)
    if changed then input_buf = new_buf end
    local input_focused = reaper.ImGui_IsItemFocused(ctx)

    reaper.ImGui_SameLine(ctx, 0, gap)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x24866FFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2A9A80FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x2A9A80FF)
    local apply_clicked = reaper.ImGui_Button(ctx, "Apply", apply_width, input_height)
    reaper.ImGui_PopStyleColor(ctx, 3)

    local enter_pressed = input_focused and (
        reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter())
        or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter())
    )
    if (apply_clicked or enter_pressed) and #targets > 0 then
        ApplyRename(mode, targets, input_buf)
    end
    reaper.ImGui_EndDisabled(ctx)

    reaper.ImGui_PopStyleVar(ctx, 1)
    if input_font then reaper.ImGui_PopFont(ctx) end

    -- Compact options row. Number (_nn) exposes a start-index input when enabled;
    -- the two checkboxes retain a small gap and Open Renamer shares the row.
    local options_row_y = reaper.ImGui_GetCursorPosY(ctx)
    local checkbox_height = reaper.ImGui_GetFrameHeight(ctx)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 8, 0)
    local number_changed, new_number = reaper.ImGui_Checkbox(ctx, "Number (_nn)", use_number)
    if number_changed then
        use_number = new_number
        SaveSettings()
    end

    if use_number then
        reaper.ImGui_SameLine(ctx, 0, 4)
        reaper.ImGui_SetNextItemWidth(ctx, 64)
        local start_changed, new_start = reaper.ImGui_InputText(
            ctx, "##RenamerLiteNumberStart", number_start_text
        )
        if start_changed then
            number_start_text = new_start
            -- Plain text input: no +/- stepper buttons. Keep the edit buffer
            -- as text so multi-digit values can be typed naturally.
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

    reaper.ImGui_SameLine(ctx, 0, 8)
    local top_changed, new_top = reaper.ImGui_Checkbox(ctx, "Top-Level Only", top_level_only)
    if top_changed then
        top_level_only = new_top
        SaveSettings()
    end

    local open_button_width = 83 --math.max(70, properties_button_width or 112)
    local open_button_height = checkbox_height
    reaper.ImGui_SameLine(ctx, 0, 0)
    reaper.ImGui_SetCursorPosX(ctx, row_start_x + math.max(0, available_width - open_button_width))
    reaper.ImGui_SetCursorPosY(ctx, options_row_y + math.max(0, (checkbox_height - open_button_height) * 0.5))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x233C4FFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x435665FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x042239FF)
    if reaper.ImGui_Button(ctx, "Renamer", open_button_width, open_button_height) then
        local command_id = reaper.NamedCommandLookup("_RS2343473a341aa2705a7b16c73d17d2fba2912208")
        if command_id and command_id ~= 0 then
            reaper.Main_OnCommand(command_id, 0)
        else
            reaper.ShowMessageBox("JKK_Renamer command could not be found. Check the ReaScript action ID.", "JKK_ReaTools", 0)
        end
    end
    reaper.ImGui_PopStyleColor(ctx, 3)
    reaper.ImGui_PopStyleVar(ctx, 1)

    input_was_focused = input_focused
    was_active = active and #targets > 0
    last_target_signature = target_signature
    last_mode = mode
end

return {
    JKK_RenamerLite_Draw = DrawRenamerLite
}
