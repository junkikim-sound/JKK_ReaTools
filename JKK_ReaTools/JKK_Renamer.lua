--========================================================
-- @title JKK_Renamer
-- @author Junki Kim
-- @version 1.0.4
-- @provides 
--     [nomain] Modules/JKK_Renamer_UCSList.lua
--     [nomain] Modules/JKK_Renamer_WildcardList.lua
--========================================================

local r = reaper

-- 외부 모듈 로드
local info = debug.getinfo(1, 'S')
local script_path = info.source:match([[^@?(.*[\/])]]) or ""
local w_list = dofile(script_path .. "Modules/JKK_Renamer_WildcardList.lua")
local ucs_list = dofile(script_path .. "Modules/JKK_Renamer_UCSList.lua")

-- JKK_Theme.lua 안전 로드
local theme_path = r.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_Theme.lua"
if not r.file_exists(theme_path) then
    theme_path = script_path .. "Modules/JKK_Theme.lua"
end

local ApplyTheme = (r.file_exists(theme_path) and dofile(theme_path).ApplyTheme) 
                   or function(ctx) return 0, 0 end

-- ReaImGui 컨텍스트 생성 및 폰트 설정
local ctx = r.ImGui_CreateContext("JKK_Renamer")
local font_large = r.ImGui_CreateFont('sans-serif', 18)
local font = r.ImGui_CreateFont('sans-serif', 16)
local font_small = r.ImGui_CreateFont('sans-serif', 14)
r.ImGui_Attach(ctx, font_large)
r.ImGui_Attach(ctx, font)
r.ImGui_Attach(ctx, font_small)

-- InputText 키보드 콜백 (Tab 자동완성 / 위아래 화살표 선택)
local completion_callback = r.ImGui_CreateFunctionFromEEL([[
EventFlag == InputTextFlags_CallbackCompletion ? (
    tab_requested = 1;
);
EventFlag == InputTextFlags_CallbackHistory ? (
    EventKey == Key_UpArrow ? (up_requested = 1;);
    EventKey == Key_DownArrow ? (down_requested = 1;);
);
]])

-- 콜백 함수를 컨텍스트에 연결해 탭 전환 중에도 유효한 수명을 유지
r.ImGui_Attach(ctx, completion_callback)

r.ImGui_Function_SetValue(completion_callback, "InputTextFlags_CallbackCompletion",
    r.ImGui_InputTextFlags_CallbackCompletion())
r.ImGui_Function_SetValue(completion_callback, "InputTextFlags_CallbackHistory",
    r.ImGui_InputTextFlags_CallbackHistory())
r.ImGui_Function_SetValue(completion_callback, "Key_UpArrow", r.ImGui_Key_UpArrow())
r.ImGui_Function_SetValue(completion_callback, "Key_DownArrow", r.ImGui_Key_DownArrow())
r.ImGui_Function_SetValue(completion_callback, "tab_requested", 0)
r.ImGui_Function_SetValue(completion_callback, "up_requested", 0)
r.ImGui_Function_SetValue(completion_callback, "down_requested", 0)

-- 마지막 ImGui 아이템에 마우스를 올렸을 때 설명 툴팁 표시
local function ShowItemTooltip(message)
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_BeginTooltip(ctx) then
        r.ImGui_Text(ctx, message)
        r.ImGui_EndTooltip(ctx)
    end
end

-- 설정값 영구 저장 (REAPER ExtState)
local ext_section = "JKK_SmartBatchRenamer"
local function LoadBool(key, default)
    local value = r.GetExtState(ext_section, key)
    if value == "1" then return true end
    if value == "0" then return false end
    return default or false
end

local use_number = LoadBool("use_number", false)
local top_level_only = LoadBool("top_level_only", false)
local number_start = tonumber(r.GetExtState(ext_section, "number_start")) or 1

-- Rename 입력창은 매 실행마다 비우고, Find & Replace 입력값은 복원
local input_buf = ""
local find_buf = r.GetExtState(ext_section, "find_buf") or ""
local replace_buf = r.GetExtState(ext_section, "replace_buf") or ""
local replace_nth_only = LoadBool("replace_nth_only", false)
local replace_nth = math.max(1, tonumber(r.GetExtState(ext_section, "replace_nth")) or 1)
local remove_extension = LoadBool("remove_extension", false)
local split_camel_case = LoadBool("split_camel_case", false)
local case_mode = math.max(0, math.min(4, tonumber(r.GetExtState(ext_section, "case_mode")) or 0)) -- 0: No Change, 1: lower, 2: UPPER, 3: Title, 4: Title (keep ALL CAPS)
local split_underscore = LoadBool("split_underscore", false)
local active_tab = r.GetExtState(ext_section, "active_tab")
if active_tab ~= "FindReplace" then active_tab = "Rename" end
local restore_saved_tab = true

local function SaveState()
    r.SetExtState(ext_section, "use_number", use_number and "1" or "0", true)
    r.SetExtState(ext_section, "top_level_only", top_level_only and "1" or "0", true)
    r.SetExtState(ext_section, "number_start", tostring(number_start), true)
    r.SetExtState(ext_section, "find_buf", find_buf, true)
    r.SetExtState(ext_section, "replace_buf", replace_buf, true)
    r.SetExtState(ext_section, "replace_nth_only", replace_nth_only and "1" or "0", true)
    r.SetExtState(ext_section, "replace_nth", tostring(replace_nth), true)
    r.SetExtState(ext_section, "remove_extension", remove_extension and "1" or "0", true)
    r.SetExtState(ext_section, "split_camel_case", split_camel_case and "1" or "0", true)
    r.SetExtState(ext_section, "case_mode", tostring(case_mode), true)
    r.SetExtState(ext_section, "split_underscore", split_underscore and "1" or "0", true)
    r.SetExtState(ext_section, "active_tab", active_tab, true)
end
local set_focus = true
local select_all_on_initial_focus = true
local initial_name_initialized = false
local open = true
local popup_dismissed = false
local suppress_initial_autocomplete = true

local popup_sel_idx = 1
local trigger_char = nil
local filter_str = ""

-- 포커스 추적 상태 변수
local current_mode = "Item"
local last_ts_start, last_ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
local last_item_ptr = r.GetSelectedMediaItem(0, 0)
local last_track_ptr = r.GetSelectedTrack(0, 0)
local last_cursor_ctx = r.GetCursorContext2(true)

-- 초기 선택 상태 확인
local has_sel_mkr_rgn = false
if r.GetNumRegionsOrMarkers and r.GetRegionOrMarker and r.GetRegionOrMarkerInfo_Value then
    local num_markers, num_regions = r.GetNumRegionsOrMarkers(0)
    local total = (num_markers or 0) + (num_regions or 0)
    for idx = 0, total - 1 do
        local pm = r.GetRegionOrMarker(0, idx, "")
        if pm and r.GetRegionOrMarkerInfo_Value(0, pm, "B_UISEL") == 1 then
            has_sel_mkr_rgn = true
            break
        end
    end
end

if r.CountSelectedMediaItems(0) > 0 then current_mode = "Item"
elseif r.CountSelectedTracks(0) > 0 then current_mode = "Track"
elseif has_sel_mkr_rgn or last_ts_end > last_ts_start then current_mode = "Region/Marker" end

-- 포커스 모드 업데이트 함수
local function UpdateFocusMode()
    local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if ts_start ~= last_ts_start or ts_end ~= last_ts_end then
        current_mode = "Region/Marker"
        last_ts_start, last_ts_end = ts_start, ts_end
    end

    local current_item_ptr = r.GetSelectedMediaItem(0, 0)
    if current_item_ptr ~= last_item_ptr then
        if current_item_ptr then current_mode = "Item" end
        last_item_ptr = current_item_ptr
    end

    local current_track_ptr = r.GetSelectedTrack(0, 0)
    if current_track_ptr ~= last_track_ptr then
        if current_track_ptr then current_mode = "Track" end
        last_track_ptr = current_track_ptr
    end

    local ctx_mode = r.GetCursorContext2(true)
    if ctx_mode ~= last_cursor_ctx then
        if ctx_mode == 0 then current_mode = "Track"
        elseif ctx_mode == 1 then current_mode = "Item"
        end
        last_cursor_ctx = ctx_mode
    end

    if r.GetNumRegionsOrMarkers and r.GetRegionOrMarker and r.GetRegionOrMarkerInfo_Value then
        local num_markers, num_regions = r.GetNumRegionsOrMarkers(0)
        local total = (num_markers or 0) + (num_regions or 0)
        for idx = 0, total - 1 do
            local pm = r.GetRegionOrMarker(0, idx, "")
            if pm and r.GetRegionOrMarkerInfo_Value(0, pm, "B_UISEL") == 1 then
                if current_mode ~= "Item" and current_mode ~= "Track" then
                    current_mode = "Region/Marker"
                end
                break
            end
        end
    end
end

local function GetTargetTypeStr(target)
    if target.type == "Item" then
        local track = r.GetMediaItem_Track(target.item)
        local depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        if depth == 1 then return "Folder Item" end

        local take = r.GetActiveTake(target.item)
        if take then
            if r.TakeIsMIDI(take) then return "MIDI Item"
            else return "Audio Item" end
        end
        return "Item"
    elseif target.type == "Track" then
        local depth = r.GetMediaTrackInfo_Value(target.track, "I_FOLDERDEPTH")
        local parent = r.GetParentTrack(target.track)
        if depth == 1 then return "Folder Track" end
        if parent then return "Child Track" end
        return "Track"
    elseif target.type == "Region" then
        return "Region"
    elseif target.type == "Marker" then
        return "Marker"
    end
    return "Unknown"
end

local function GetTargets()
    local raw_targets = {}
    
    if current_mode == "Item" then
        local sel_items = r.CountSelectedMediaItems(0)
        for i = 0, sel_items - 1 do
            local item = r.GetSelectedMediaItem(0, i)
            local track = r.GetMediaItem_Track(item)
            local take = r.GetActiveTake(item)
            local name = ""
            if take then _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false) end
            table.insert(raw_targets, { type = "Item", item = item, track = track, original_name = name })
        end
    elseif current_mode == "Track" then
        local sel_tracks = r.CountSelectedTracks(0)
        for i = 0, sel_tracks - 1 do
            local track = r.GetSelectedTrack(0, i)
            local _, name = r.GetTrackName(track)
            table.insert(raw_targets, { type = "Track", track = track, original_name = name })
        end
    elseif current_mode == "Region" or current_mode == "Marker" or current_mode == "Region/Marker" then
        local sel_rgns = {}
        local sel_mkrs = {}
        
        if r.GetNumRegionsOrMarkers and r.GetRegionOrMarker and r.GetRegionOrMarkerInfo_Value then
            local num_markers, num_regions = r.GetNumRegionsOrMarkers(0)
            local total = (num_markers or 0) + (num_regions or 0)
            for idx = 0, total - 1 do
                local pm = r.GetRegionOrMarker(0, idx, "")
                if pm then
                    local is_sel = r.GetRegionOrMarkerInfo_Value(0, pm, "B_UISEL")
                    if is_sel and is_sel > 0 then
                        local isrgn = (r.GetRegionOrMarkerInfo_Value(0, pm, "B_ISREGION") == 1)
                        local pos = r.GetRegionOrMarkerInfo_Value(0, pm, "D_STARTPOS")
                        local rgnend = r.GetRegionOrMarkerInfo_Value(0, pm, "D_ENDPOS")
                        local markidx = math.floor(r.GetRegionOrMarkerInfo_Value(0, pm, "I_NUMBER") + 0.5)
                        local color = math.floor(r.GetRegionOrMarkerInfo_Value(0, pm, "I_CUSTOMCOLOR") + 0.5)
                        local _, name = r.GetSetRegionOrMarkerInfo_String(0, pm, "P_NAME", "", false)
                        
                        if isrgn then
                            table.insert(sel_rgns, { type = "Region", pm = pm, index = markidx, is_region = true, pos = pos, rgnend = rgnend, color = color, original_name = name or "" })
                        else
                            table.insert(sel_mkrs, { type = "Marker", pm = pm, index = markidx, is_region = false, pos = pos, rgnend = 0, color = color, original_name = name or "" })
                        end
                    end
                end
            end
        end

        if #sel_rgns > 0 or #sel_mkrs > 0 then
            for _, rgn in ipairs(sel_rgns) do table.insert(raw_targets, rgn) end
            for _, mkr in ipairs(sel_mkrs) do table.insert(raw_targets, mkr) end
        else
            local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
            if ts_end > ts_start then
                local idx = 0
                while true do
                    local retval, isrgn, pos, rgnend, name, markidx, color = r.EnumProjectMarkers3(0, idx)
                    if retval == 0 then break end
                    if isrgn then
                        if pos < ts_end and rgnend > ts_start then
                            table.insert(raw_targets, { type = "Region", index = markidx, is_region = true, pos = pos, rgnend = rgnend, color = color, original_name = name })
                        end
                    else
                        if pos >= ts_start and pos <= ts_end then
                            table.insert(raw_targets, { type = "Marker", index = markidx, is_region = false, pos = pos, rgnend = 0, color = color, original_name = name })
                        end
                    end
                    idx = idx + 1
                end
            end
        end
    end

    if not top_level_only then return raw_targets end

    local filtered = {}
    if current_mode == "Track" then
        local sel_map = {}
        for _, t in ipairs(raw_targets) do sel_map[t.track] = true end
        
        for _, t in ipairs(raw_targets) do
            local parent = r.GetParentTrack(t.track)
            local has_sel_parent = false
            while parent do
                if sel_map[parent] then
                    has_sel_parent = true
                    break
                end
                parent = r.GetParentTrack(parent)
            end
            if not has_sel_parent then
                table.insert(filtered, t)
            end
        end
    elseif current_mode == "Item" then
        local sel_tracks = {}
        for _, t in ipairs(raw_targets) do sel_tracks[t.track] = true end
        
        for _, t in ipairs(raw_targets) do
            local parent = r.GetParentTrack(t.track)
            local has_sel_parent = false
            while parent do
                if sel_tracks[parent] then
                    has_sel_parent = true
                    break
                end
                parent = r.GetParentTrack(parent)
            end
            if not has_sel_parent then
                table.insert(filtered, t)
            end
        end
    else
        filtered = raw_targets
    end

    return filtered
end

local function BuildHierarchyIndices(targets)
    local indices = {}
    
    if current_mode == "Track" then
        local sel_tracks_set = {}
        local has_any_parent_child_rel = false
        
        for _, target in ipairs(targets) do
            sel_tracks_set[target.track] = true
        end

        for _, target in ipairs(targets) do
            local parent = r.GetParentTrack(target.track)
            while parent do
                if sel_tracks_set[parent] then
                    has_any_parent_child_rel = true
                    break
                end
                parent = r.GetParentTrack(parent)
            end
            if has_any_parent_child_rel then break end
        end

        if not has_any_parent_child_rel then
            for i = 1, #targets do
                indices[i] = string.format("%02d", (number_start - 1) + i)
            end
            return indices
        end

        local track_indices = {}
        local child_counters = {}
        local root_counter = number_start - 1

        for i, target in ipairs(targets) do
            local track = target.track
            local parent = r.GetParentTrack(track)
            local sel_parent = nil
            
            while parent do
                if sel_tracks_set[parent] then
                    sel_parent = parent
                    break
                end
                parent = r.GetParentTrack(parent)
            end

            if not sel_parent then
                root_counter = root_counter + 1
                local str_idx = string.format("%02d", root_counter)
                track_indices[track] = str_idx
                indices[i] = str_idx
            else
                local parent_idx_str = track_indices[sel_parent] or string.format("%02d", number_start)
                child_counters[sel_parent] = (child_counters[sel_parent] or 0) + 1
                local child_num = string.format("%02d", child_counters[sel_parent])
                
                local str_idx = parent_idx_str .. "_" .. child_num
                track_indices[track] = str_idx
                indices[i] = str_idx
            end
        end

    elseif current_mode == "Item" then
        local sel_tracks_set = {}
        local has_any_parent_child_rel = false

        for _, target in ipairs(targets) do
            sel_tracks_set[target.track] = true
        end

        for _, target in ipairs(targets) do
            local parent = r.GetParentTrack(target.track)
            while parent do
                if sel_tracks_set[parent] then
                    has_any_parent_child_rel = true
                    break
                end
                parent = r.GetParentTrack(parent)
            end
            if has_any_parent_child_rel then break end
        end

        if not has_any_parent_child_rel then
            for i = 1, #targets do
                indices[i] = string.format("%02d", (number_start - 1) + i)
            end
            return indices
        end

        local track_base_indices = {}
        local child_item_counters = {}
        local top_item_counter = number_start - 1
        local top_track_counter = number_start - 1

        for i, target in ipairs(targets) do
            local trk = target.track
            local parent = r.GetParentTrack(trk)
            local sel_parent = nil

            while parent do
                if sel_tracks_set[parent] then
                    sel_parent = parent
                    break
                end
                parent = r.GetParentTrack(parent)
            end

            if not sel_parent then
                top_item_counter = top_item_counter + 1
                local str_idx = string.format("%02d", top_item_counter)
                
                if not track_base_indices[trk] then
                    track_base_indices[trk] = str_idx
                end
                
                indices[i] = str_idx
            else
                local parent_idx_str = track_base_indices[sel_parent]
                if not parent_idx_str then
                    top_track_counter = top_track_counter + 1
                    parent_idx_str = string.format("%02d", top_track_counter)
                    track_base_indices[sel_parent] = parent_idx_str
                end

                child_item_counters[trk] = (child_item_counters[trk] or 0) + 1
                local child_num = string.format("%02d", child_item_counters[trk])

                local str_idx = parent_idx_str .. "_" .. child_num
                track_base_indices[trk] = str_idx
                indices[i] = str_idx
            end
        end
    else
        for i = 1, #targets do
            indices[i] = string.format("%02d", (number_start - 1) + i)
        end
    end
    
    return indices
end

local function EvaluateName(pattern, target, index, hierarchy_indices)
    local out = pattern
    if out == "" then return "" end

    local p_name = r.GetProjectName(0, ""):gsub("%.%w+$", "")
    out = out:gsub("%$project", p_name)
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
        local _, t_name = r.GetTrackName(target.track)
        out = out:gsub("%$track", t_name)
        out = out:gsub("%$item", target.original_name)
        out = out:gsub("%$region", "")
        out = out:gsub("%$marker", "")
    elseif target.type == "Track" then
        out = out:gsub("%$track", target.original_name)
        out = out:gsub("%$item", "")
        out = out:gsub("%$region", "")
        out = out:gsub("%$marker", "")
    elseif target.type == "Region" or target.type == "Marker" then
        out = out:gsub("%$region", target.original_name)
        out = out:gsub("%$marker", target.original_name)
        out = out:gsub("%$track", "")
        out = out:gsub("%$item", "")
    end

    if out:find("%$filenumber%[%d+%]") then
        local num_str = hierarchy_indices and hierarchy_indices[index] or string.format("%02d", (number_start - 1) + index)
        out = out:gsub("%$filenumber%[%d+%]", num_str)
    end
    
    if out:find("%$uniqueid%[[%wN]+%]") then
        out = out:gsub("%$uniqueid%[[%wN]+%]", "ID" .. tostring(math.random(1000, 9999)))
    end

    if use_number and not pattern:find("%$filenumber%[%d+%]") then
        local num_str = hierarchy_indices and hierarchy_indices[index] or string.format("%02d", (number_start - 1) + index)
        out = out .. "_" .. num_str
    end
    return out
end

local function ReplaceLiteral(text, find_text, replace_text, nth_only, nth)
    if find_text == "" then return text end

    local output = {}
    local cursor = 1
    local occurrence = 0

    while cursor <= #text + 1 do
        local first, last = text:find(find_text, cursor, true)
        if not first then
            table.insert(output, text:sub(cursor))
            break
        end

        occurrence = occurrence + 1
        table.insert(output, text:sub(cursor, first - 1))

        if not nth_only or occurrence == nth then
            table.insert(output, replace_text)
        else
            table.insert(output, text:sub(first, last))
        end

        cursor = last + 1

        if nth_only and occurrence >= nth then
            table.insert(output, text:sub(cursor))
            break
        end
    end

    return table.concat(output)
end

local function SplitCamelWords(text)
    -- lower/digit -> Upper boundary (helloWorld -> hello World)
    text = text:gsub("([%l%d])([%u])", "%1 %2")
    -- acronym -> CapitalizedWord boundary (HTTPServer -> HTTP Server)
    text = text:gsub("([%u])([%u][%l])", "%1 %2")
    return text
end

local function TransformCaseWord(word, mode)
    if mode == 1 then
        return word:lower()
    elseif mode == 2 then
        return word:upper()
    elseif mode == 3 then
        return word:lower():gsub("^%l", string.upper)
    elseif mode == 4 then
        if word:find("%a") and word == word:upper() then
            return word
        end
        return word:lower():gsub("^%l", string.upper)
    end
    return word
end

local function ApplyFindReplaceName(original_name, index, hierarchy_indices)
    local result = original_name or ""

    -- 1. Find & Replace (기본: 모든 일치 항목, 선택 시 N번째 항목만)
    result = ReplaceLiteral(result, find_buf, replace_buf, replace_nth_only, replace_nth)

    -- 2. 파일 확장자 제거
    if remove_extension then
        result = result:gsub("%.[^%.]+$", "")
    end

    -- 3. CamelCase / PascalCase 단어 분리
    if split_camel_case then
        result = SplitCamelWords(result)
    end

    -- 4. 대소문자 재정의
    if case_mode ~= 0 then
        if split_underscore then
            result = result:gsub("([^%s_]+)", function(word)
                return TransformCaseWord(word, case_mode)
            end)
        else
            result = result:gsub("([^%s]+)", function(word)
                return TransformCaseWord(word, case_mode)
            end)
        end
    end

    -- 5. 기존 넘버링 옵션 유지
    if use_number then
        local number_text = hierarchy_indices and hierarchy_indices[index]
            or string.format("%02d", (number_start - 1) + index)
        result = result .. "_" .. number_text
    end

    return result
end

local function SetTargetName(target, new_name)
    if target.type == "Item" then
        local take = r.GetActiveTake(target.item)
        if take then r.GetSetMediaItemTakeInfo_String(take, "P_NAME", new_name, true) end
    elseif target.type == "Track" then
        r.GetSetMediaTrackInfo_String(target.track, "P_NAME", new_name, true)
    elseif target.type == "Region" or target.type == "Marker" then
        if target.pm and r.GetSetRegionOrMarkerInfo_String then
            r.GetSetRegionOrMarkerInfo_String(0, target.pm, "P_NAME", new_name, true)
        else
            r.SetProjectMarker3(0, target.index, target.is_region, target.pos, target.rgnend, new_name, target.color or 0)
        end
    end
end

local function ApplyFindReplace(targets, hierarchy_indices)
    if find_buf == "" and not remove_extension and not split_camel_case
        and case_mode == 0 and not use_number then
        return
    end

    r.Undo_BeginBlock()
    for i, target in ipairs(targets) do
        local new_name = ApplyFindReplaceName(target.original_name, i, hierarchy_indices)
        if new_name ~= (target.original_name or "") then
            SetTargetName(target, new_name)
        end
    end
    r.Undo_EndBlock("JKK Renamer - Find & Replace", -1)
    r.UpdateArrange()
end

local function ApplyRename(targets, hierarchy_indices)
    if input_buf == "" then return end
    r.Undo_BeginBlock()
    
    for i, target in ipairs(targets) do
        local new_name = EvaluateName(input_buf, target, i, hierarchy_indices)
        
        SetTargetName(target, new_name)
    end
    
    r.Undo_EndBlock("Smart Batch Rename", -1)
    r.UpdateArrange()
end

local function Main()
    r.ImGui_PushFont(ctx, font, 16)
    r.ImGui_SetNextWindowSize(ctx, 840, 480, r.ImGui_Cond_FirstUseEver())
    
    -- 윈도우 최소 크기 한계점 설정 (가로 700px, 세로 320px)
    r.ImGui_SetNextWindowSizeConstraints(ctx, 700, 320, 16384, 16384)

    local style_pop_count, color_pop_count = ApplyTheme(ctx)

    -- 5. 창 타이틀바 이름 JKK_Renamer 적용
    local visible, open_flag = r.ImGui_Begin(ctx, 'JKK_Renamer', open, r.ImGui_WindowFlags_NoCollapse())
    open = open_flag

    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
        open = false
    end

    if visible then
        UpdateFocusMode()
        
        local targets = GetTargets()
        local target_count = #targets

        -- 첫 화면에서는 현재 선택된 첫 번째 항목의 이름을 입력값으로 사용한다.
        -- 입력창은 최초 포커스 시 전체 선택되어 바로 새 이름을 입력할 수 있다.
        if not initial_name_initialized then
            if target_count > 0 then
                input_buf = targets[1].original_name or ""
            end
            initial_name_initialized = true
            set_focus = true
            select_all_on_initial_focus = true
        end
        
        local hierarchy_indices = nil
        if use_number and not top_level_only then
            hierarchy_indices = BuildHierarchyIndices(targets)
        end

        r.ImGui_PushFont(ctx, font_small, 14)
        local target_type_text = (current_mode == "Region/Marker" or current_mode == "Region" or current_mode == "Marker") and "regions/markers" or (current_mode:lower() .. "s")
        if target_count == 0 then
            r.ImGui_TextColored(ctx, 0xE3DB8EFF, string.format("0 %s selected", target_type_text))
        else
            r.ImGui_TextColored(ctx, 0xE3DB8EFF, string.format("Rename %d %s", target_count, target_type_text))
        end
        r.ImGui_Spacing(ctx)
        
        if r.ImGui_BeginTabBar(ctx, "RenamerTabs") then
        local rename_tab_flags = (restore_saved_tab and active_tab == "Rename")
            and r.ImGui_TabItemFlags_SetSelected() or 0
        if r.ImGui_BeginTabItem(ctx, "Rename", rename_tab_flags) then
        if not restore_saved_tab and active_tab ~= "Rename" then
            active_tab = "Rename"
            SaveState()
        end
        r.ImGui_Spacing(ctx)

        local apply_btn_w = 90
        local input_w = r.ImGui_GetContentRegionAvail(ctx) - apply_btn_w - 8
        
        local initial_select_all_flag = 0
        if set_focus then
            r.ImGui_SetKeyboardFocusHere(ctx, 0)
            set_focus = false
            if select_all_on_initial_focus then
                initial_select_all_flag = r.ImGui_InputTextFlags_AutoSelectAll()
                select_all_on_initial_focus = false
            end
        end

        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 8)
        r.ImGui_PushFont(ctx, font_large, 18)
        
        r.ImGui_SetNextItemWidth(ctx, input_w)
        local hint_text = (target_count > 0) and targets[1].original_name or "Enter new name..."
        
        local input_rect_min_x, input_rect_min_y = r.ImGui_GetCursorScreenPos(ctx)
        
        -- 콜백 이벤트 플래그 초기화
        r.ImGui_Function_SetValue(completion_callback, "tab_requested", 0)
        r.ImGui_Function_SetValue(completion_callback, "up_requested", 0)
        r.ImGui_Function_SetValue(completion_callback, "down_requested", 0)

        -- Tab / 위아래 화살표를 InputText 내부 콜백에서 처리
        local input_flags = r.ImGui_InputTextFlags_CallbackCompletion()
                        | r.ImGui_InputTextFlags_CallbackHistory()
                        | initial_select_all_flag

        local changed, new_buf = r.ImGui_InputTextWithHint(
            ctx,
            "##RenameInput",
            hint_text,
            input_buf,
            input_flags,
            completion_callback
        )

        local is_focused = r.ImGui_IsItemFocused(ctx)

        if changed then
            local old_buf = input_buf
            input_buf = new_buf
            suppress_initial_autocomplete = false

            if new_buf:sub(-1) == "$" or new_buf:sub(-1) == "!"
                or (new_buf:len() > old_buf:len()
                and new_buf:sub(#old_buf + 1):find("[$!]")) then

                popup_dismissed = false
            end
        end

        -- 콜백에서 전달된 키 입력 이벤트 확인
        local tab_requested = r.ImGui_Function_GetValue(completion_callback, "tab_requested") == 1
        local up_requested = r.ImGui_Function_GetValue(completion_callback, "up_requested") == 1
        local down_requested = r.ImGui_Function_GetValue(completion_callback, "down_requested") == 1
        local keyboard_popup_event = tab_requested or up_requested or down_requested

        -- 키보드 콜백으로 팝업을 조작하는 중에는 포커스 이탈로 닫지 않음
        if not is_focused and not keyboard_popup_event then
            popup_dismissed = true
        end

        local input_rect_max_x, input_rect_max_y = r.ImGui_GetItemRectMax(ctx)
        
        r.ImGui_PopFont(ctx)
        r.ImGui_PopStyleVar(ctx)
        
        -- 4. Apply 버튼 텍스트 세로 중앙 정렬 보정 (패딩 y: 5px)
        r.ImGui_SameLine(ctx, 0, 8)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 5)
        r.ImGui_PushFont(ctx, font_large, 18)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x24866FFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x2A9A80FF)
        if r.ImGui_Button(ctx, "Apply", apply_btn_w, 41) then
            ApplyRename(targets, hierarchy_indices)
            open = false
        end
        r.ImGui_PopStyleColor(ctx, 2)
        r.ImGui_PopFont(ctx)
        r.ImGui_PopStyleVar(ctx)

        local clean_search_buf = input_buf:gsub("[%s\t]+$", "")
        local trg_char, flt_str = clean_search_buf:match(".*([$!])([^%s$!]*)$")
        
        -- 트리거 문자가 지워진 경우 다음 $ / ! 입력을 위해 팝업 차단 해제
        if trg_char == nil then
            popup_dismissed = false
        end

        -- 포커스 유효 및 차단 해제 상태에서만 팝업 표시
        local show_popup = (is_focused or keyboard_popup_event)
            and not popup_dismissed
            and not suppress_initial_autocomplete
            and (trg_char ~= nil)
            and not input_buf:match("%s$")
        trigger_char, filter_str = trg_char, flt_str
        local filtered = {}

        if show_popup then
            local src_list = trigger_char == "$" and w_list or ucs_list
            local search = (filter_str or ""):lower()

            for _, item in ipairs(src_list) do
                local target_str = (trigger_char == "$" and item.insert:sub(2) or item.insert):lower()
                local cat_str = (item.cat or ""):lower()
                local sub_str = (item.sub or ""):lower()
                local name_str = (item.name or ""):lower()
                local desc_str = (item.desc or ""):lower()

                if search == "" then
                    table.insert(filtered, { item = item, score = 0 })
                else
                    local score = -1
                    if target_str:sub(1, #search) == search then
                        score = 1000 - #target_str
                    elseif cat_str:sub(1, #search) == search then
                        score = 900 - #cat_str
                    elseif target_str:find(search, 1, true) then
                        score = 800 - #target_str
                    elseif sub_str:sub(1, #search) == search then
                        score = 700 - #sub_str
                    elseif name_str:find(search, 1, true) or desc_str:find(search, 1, true) then
                        score = 500 - #desc_str
                    end

                    if score > -1 then
                        table.insert(filtered, { item = item, score = score })
                    end
                end
            end

            if search ~= "" then
                table.sort(filtered, function(a, b) return a.score > b.score end)
            end

            local sorted_items = {}
            for _, entry in ipairs(filtered) do table.insert(sorted_items, entry.item) end
            filtered = sorted_items

            if #filtered == 0 then show_popup = false end
        end

        popup_sel_idx = math.max(1, math.min(popup_sel_idx, #filtered > 0 and #filtered or 1))

        -- InputText 콜백에서 전달된 위아래 화살표로 팝업 항목 선택
        if show_popup then
            if up_requested then
                popup_sel_idx = math.max(1, popup_sel_idx - 1)
            elseif down_requested then
                popup_sel_idx = math.min(#filtered, popup_sel_idx + 1)
            end
        end

        -- Tab은 현재 검색 결과의 첫 번째 항목을 자동완성
        if show_popup and tab_requested then
            local selected = filtered[1]
            if selected then
                if trigger_char == "$" then
                    input_buf = clean_search_buf:gsub("%$[^%s$!]*$", selected.insert .. " ")
                elseif trigger_char == "!" then
                    input_buf = clean_search_buf:gsub("![^%s$!]*$", selected.insert .. " ")
                end
                popup_dismissed = true
                show_popup = false
                set_focus = true
            end
        end

        -- ENTER 키 처리 (팝업 열림: 자동완성 적용 / 팝업 닫힘: 리네이밍 적용 및 종료)
        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) or r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_KeypadEnter()) then
            if show_popup then
                local selected = filtered[popup_sel_idx]
                if selected then
                    if trigger_char == "$" then
                        input_buf = clean_search_buf:gsub("%$[^%s$!]*$", selected.insert .. " ")
                    elseif trigger_char == "!" then
                        input_buf = clean_search_buf:gsub("![^%s$!]*$", selected.insert .. " ")
                    end
                    popup_dismissed = true
                    show_popup = false
                    set_focus = true
                end
            else
                ApplyRename(targets, hierarchy_indices)
                open = false
            end
        end

        r.ImGui_Spacing(ctx)
        r.ImGui_PushFont(ctx, font_small, 14)
        
        local chk_changed, new_chk = r.ImGui_Checkbox(ctx, " Number (_nn)", use_number)
        if chk_changed then 
            use_number = new_chk 
            SaveState()
        end
        
        if use_number then
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 45)
            local num_changed, new_num = r.ImGui_InputInt(ctx, "##NumStart", number_start, 0)
            if num_changed then
                number_start = new_num
                SaveState()
            end
        end
        
        r.ImGui_SameLine(ctx, 0, 20)
        local top_changed, new_top = r.ImGui_Checkbox(ctx, " Top-Level Only", top_level_only)
        if top_changed then 
            top_level_only = new_top 
            SaveState()
        end

        r.ImGui_PopFont(ctx)
        
        r.ImGui_Separator(ctx)

        -- 2 & 3. Preview Container: Child Window 배경 추가 + 좌측 Indent 패딩 및 라운딩 부여
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 8)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 6.0)
        
        local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
        if r.ImGui_BeginChild(ctx, "PreviewContainer", avail_w, avail_h, r.ImGui_ChildFlags_Borders()) then
            r.ImGui_Indent(ctx, 6)
            r.ImGui_Spacing(ctx)

            if target_count > 0 then
                r.ImGui_PushFont(ctx, font_small, 14)
                if r.ImGui_BeginTable(ctx, "PreviewTable", 4, r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_ScrollY()) then
                    r.ImGui_TableSetupColumn(ctx, "Type", r.ImGui_TableColumnFlags_WidthFixed(), 110)
                    r.ImGui_TableSetupColumn(ctx, "Before", r.ImGui_TableColumnFlags_WidthStretch())
                    r.ImGui_TableSetupColumn(ctx, "##BeforeAfterDivider", r.ImGui_TableColumnFlags_WidthFixed(), 18)
                    r.ImGui_TableSetupColumn(ctx, "After", r.ImGui_TableColumnFlags_WidthStretch())

                    for i, target in ipairs(targets) do
                        r.ImGui_TableNextRow(ctx)

                        -- 종류
                        r.ImGui_TableNextColumn(ctx)
                        r.ImGui_TextColored(ctx, 0x888888FF, GetTargetTypeStr(target))

                        -- 변경 전 이름
                        r.ImGui_TableNextColumn(ctx)
                        r.ImGui_Text(ctx, target.original_name or "")

                        -- Before / After 구분선
                        r.ImGui_TableNextColumn(ctx)
                        r.ImGui_TextColored(ctx, 0x555555FF, "│")

                        -- 변경 후 이름
                        r.ImGui_TableNextColumn(ctx)
                        local evaluated = EvaluateName(input_buf, target, i, hierarchy_indices)
                        r.ImGui_TextColored(ctx, 0xE3DB8EFF,
                            evaluated == "" and (target.original_name or "") or evaluated)
                    end
                    r.ImGui_EndTable(ctx)
                end
                r.ImGui_PopFont(ctx)
            else
                r.ImGui_PushFont(ctx, font_small, 14)
                r.ImGui_TextColored(ctx, 0x666666FF, "No items selected.")
                r.ImGui_PopFont(ctx)
            end

            r.ImGui_Unindent(ctx, 6)
            r.ImGui_EndChild(ctx)
        end
        r.ImGui_PopStyleVar(ctx, 2)

        if show_popup then
            r.ImGui_SetNextWindowPos(ctx, input_rect_min_x, input_rect_max_y + 4)
            r.ImGui_SetNextWindowSize(ctx, input_w, 420)
            
            local popup_flags = r.ImGui_WindowFlags_NoTitleBar() 
                              | r.ImGui_WindowFlags_NoResize() 
                              | r.ImGui_WindowFlags_NoMove() 
                              | r.ImGui_WindowFlags_NoSavedSettings()
                              | r.ImGui_WindowFlags_NoFocusOnAppearing()
            
            if r.ImGui_Begin(ctx, "AutoCompletePopup", true, popup_flags) then
                
                r.ImGui_PushFont(ctx, font_small, 14)
                
                local table_flags = r.ImGui_TableFlags_RowBg() 
                                  | r.ImGui_TableFlags_BordersInnerV()
                                  | r.ImGui_TableFlags_ScrollX() 
                                  | r.ImGui_TableFlags_ScrollY()

                if r.ImGui_BeginTable(ctx, "PopupTable", trigger_char == "$" and 3 or 4, table_flags) then
                    
                    if trigger_char == "$" then
                        r.ImGui_TableSetupColumn(ctx, "Wildcard", r.ImGui_TableColumnFlags_WidthFixed(), 140)
                        r.ImGui_TableSetupColumn(ctx, "Name", r.ImGui_TableColumnFlags_WidthFixed(), 150)
                        r.ImGui_TableSetupColumn(ctx, "Description", r.ImGui_TableColumnFlags_WidthStretch())
                    else
                        r.ImGui_TableSetupColumn(ctx, "CatID", r.ImGui_TableColumnFlags_WidthFixed(), 100)
                        r.ImGui_TableSetupColumn(ctx, "Category", r.ImGui_TableColumnFlags_WidthFixed(), 140)
                        r.ImGui_TableSetupColumn(ctx, "SubCategory", r.ImGui_TableColumnFlags_WidthFixed(), 140)
                        r.ImGui_TableSetupColumn(ctx, "Description", r.ImGui_TableColumnFlags_WidthFixed(), 500)
                    end
                    
                    r.ImGui_TableHeadersRow(ctx)

                    for i, item in ipairs(filtered) do
                        r.ImGui_TableNextRow(ctx)
                        
                        local is_selected = (i == popup_sel_idx)
                        if is_selected then 
                            r.ImGui_TableSetBgColor(ctx, r.ImGui_TableBgTarget_RowBg0(), 0x335588FF)
                        end

                        r.ImGui_TableNextColumn(ctx)
                        
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xE3DB8EFF)
                        local display_text = item.insert
                        if r.ImGui_Selectable(ctx, display_text .. "##" .. tostring(i), false, r.ImGui_SelectableFlags_SpanAllColumns()) then
                            if trigger_char == "$" then
                                input_buf = clean_search_buf:gsub("%$[^%s$!]*$", item.insert .. " ")
                            elseif trigger_char == "!" then
                                input_buf = clean_search_buf:gsub("![^%s$!]*$", item.insert .. " ")
                            end
                            popup_dismissed = true
                            show_popup = false
                            set_focus = true
                        end
                        r.ImGui_PopStyleColor(ctx)
                        
                        if r.ImGui_IsItemHovered(ctx) then popup_sel_idx = i end

                        if trigger_char == "$" then
                            r.ImGui_TableNextColumn(ctx)
                            r.ImGui_Text(ctx, item.name)
                            r.ImGui_TableNextColumn(ctx)
                            r.ImGui_TextColored(ctx, 0x999999FF, item.desc)
                        else
                            r.ImGui_TableNextColumn(ctx)
                            r.ImGui_Text(ctx, item.cat)
                            r.ImGui_TableNextColumn(ctx)
                            r.ImGui_Text(ctx, item.sub)
                            r.ImGui_TableNextColumn(ctx)
                            r.ImGui_TextColored(ctx, 0x999999FF, item.desc)
                        end
                    end
                    r.ImGui_EndTable(ctx)
                end
                r.ImGui_PopFont(ctx)
                r.ImGui_End(ctx)
            end
        else
            popup_sel_idx = 1
        end

        r.ImGui_EndTabItem(ctx)
        end -- Rename tab

        local find_tab_flags = (restore_saved_tab and active_tab == "FindReplace")
            and r.ImGui_TabItemFlags_SetSelected() or 0
        if r.ImGui_BeginTabItem(ctx, "Find & Replace", find_tab_flags) then
            if not restore_saved_tab and active_tab ~= "FindReplace" then
                active_tab = "FindReplace"
                SaveState()
            end

            -- Find / Replace: 왼쪽 라벨, 오른쪽 동일 너비 입력창, 우측 세로형 Apply 버튼
            local fr_width = r.ImGui_GetContentRegionAvail(ctx)
            local apply_width = 90
            local label_width = 68
            local input_width = math.max(140, fr_width - apply_width - label_width - 8)
            r.ImGui_Spacing(ctx)

            r.ImGui_BeginGroup(ctx)
            r.ImGui_Text(ctx, "Find")
            r.ImGui_SameLine(ctx, label_width, 0)
            r.ImGui_SetNextItemWidth(ctx, input_width)
            local find_changed, new_find = r.ImGui_InputTextWithHint(ctx, "##FindText", "Text to find...", find_buf)
            if find_changed then
                find_buf = new_find
                SaveState()
            end

            r.ImGui_Text(ctx, "Replace")
            r.ImGui_SameLine(ctx, label_width, 0)
            r.ImGui_SetNextItemWidth(ctx, input_width)
            local replace_changed, new_replace = r.ImGui_InputTextWithHint(ctx, "##ReplaceText", "Replace with...", replace_buf)
            if replace_changed then
                replace_buf = new_replace
                SaveState()
            end
            r.ImGui_EndGroup(ctx)

            r.ImGui_SameLine(ctx, 0, 8)
            r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) - 2)
            r.ImGui_PushFont(ctx, font_large, 18)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x24866FFF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x2A9A80FF)
            if r.ImGui_Button(ctx, "Apply", apply_width, 64) then
                ApplyFindReplace(targets, hierarchy_indices)
            end
            r.ImGui_PopFont(ctx)
            r.ImGui_PopStyleColor(ctx, 2)

            r.ImGui_PushFont(ctx, font_small, 14)

            local nth_changed, nth_value = r.ImGui_Checkbox(ctx, "Nth only", replace_nth_only)
            if nth_changed then
                replace_nth_only = nth_value
                SaveState()
            end
            ShowItemTooltip("Replace only the specified occurrence of the Find text.")
            if replace_nth_only then
                r.ImGui_SameLine(ctx, 0, 6)
                r.ImGui_SetNextItemWidth(ctx, 58)
                local num_changed, num_value = r.ImGui_InputInt(ctx, "##FindReplaceNth", replace_nth, 0)
                if num_changed then
                    replace_nth = math.max(1, num_value)
                    SaveState()
                end
            end

            r.ImGui_SameLine(ctx, 0, 14)
            local ext_changed, ext_value = r.ImGui_Checkbox(ctx, "No extension", remove_extension)
            if ext_changed then
                remove_extension = ext_value
                SaveState()
            end
            ShowItemTooltip("Remove the file extension from the renamed filename.")

            r.ImGui_SameLine(ctx, 0, 14)
            local camel_changed, camel_value = r.ImGui_Checkbox(ctx, "Split cases", split_camel_case)
            if camel_changed then
                split_camel_case = camel_value
                SaveState()
            end
            ShowItemTooltip("Split camelCase and PascalCase words with spaces.")

            r.ImGui_SameLine(ctx, 0, 16)
            r.ImGui_SetNextItemWidth(ctx, 225)
            local case_changed, case_value = r.ImGui_Combo(ctx, "Case", case_mode,
                " No Change\0 lowercase\0 UPPERCASE\0 Title Case\0 Title Case (Keep ALL CAPS)\0")
            if case_changed then
                case_mode = case_value
                SaveState()
            end
            r.ImGui_SameLine(ctx, 0, 16)
            local underscore_changed, underscore_value = r.ImGui_Checkbox(ctx, "Split _ words", split_underscore)
            if underscore_changed then
                split_underscore = underscore_value
                SaveState()
            end
            ShowItemTooltip("Treat underscores as word separators when applying Title Case.")

            r.ImGui_Spacing(ctx)
            local number_changed, number_value = r.ImGui_Checkbox(ctx, " Number (_nn)", use_number)
            if number_changed then
                use_number = number_value
                SaveState()
            end
            if use_number then
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 55)
                local num_changed, num_value = r.ImGui_InputInt(ctx, "##FindReplaceNumStart", number_start, 0)
                if num_changed then
                    number_start = num_value
                    SaveState()
                end
            end
            r.ImGui_SameLine(ctx, 0, 20)
            local top_changed, top_value = r.ImGui_Checkbox(ctx, " Top-Level Only", top_level_only)
            if top_changed then
                top_level_only = top_value
                SaveState()
                targets = GetTargets()
                target_count = #targets
                hierarchy_indices = (use_number and not top_level_only) and BuildHierarchyIndices(targets) or nil
            end

            r.ImGui_PopFont(ctx)
            r.ImGui_Separator(ctx)

            -- Find & Replace Preview (Type / Before / After)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 8)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 6.0)
            local preview_w, preview_h = r.ImGui_GetContentRegionAvail(ctx)
            if r.ImGui_BeginChild(ctx, "FindReplacePreviewContainer", preview_w, preview_h, r.ImGui_ChildFlags_Borders()) then
                r.ImGui_Indent(ctx, 6)
                r.ImGui_Spacing(ctx)
                if target_count > 0 then
                    r.ImGui_PushFont(ctx, font_small, 14)
                    if r.ImGui_BeginTable(ctx, "FindReplacePreviewTable", 4,
                        r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_ScrollY()) then
                        r.ImGui_TableSetupColumn(ctx, "Type", r.ImGui_TableColumnFlags_WidthFixed(), 110)
                        r.ImGui_TableSetupColumn(ctx, "Before", r.ImGui_TableColumnFlags_WidthStretch())
                        r.ImGui_TableSetupColumn(ctx, "##BeforeAfterDivider", r.ImGui_TableColumnFlags_WidthFixed(), 18)
                        r.ImGui_TableSetupColumn(ctx, "After", r.ImGui_TableColumnFlags_WidthStretch())
                        for i, target in ipairs(targets) do
                            r.ImGui_TableNextRow(ctx)
                            r.ImGui_TableNextColumn(ctx)
                            r.ImGui_TextColored(ctx, 0x888888FF, GetTargetTypeStr(target))
                            r.ImGui_TableNextColumn(ctx)
                            r.ImGui_Text(ctx, target.original_name or "")
                            r.ImGui_TableNextColumn(ctx)
                            r.ImGui_TextColored(ctx, 0x555555FF, "│")
                            r.ImGui_TableNextColumn(ctx)
                            local evaluated = ApplyFindReplaceName(target.original_name, i, hierarchy_indices)
                            r.ImGui_TextColored(ctx, 0xE3DB8EFF, evaluated)
                        end
                        r.ImGui_EndTable(ctx)
                    end
                    r.ImGui_PopFont(ctx)
                else
                    r.ImGui_PushFont(ctx, font_small, 14)
                    r.ImGui_TextColored(ctx, 0x666666FF, "No items selected.")
                    r.ImGui_PopFont(ctx)
                end
                r.ImGui_Unindent(ctx, 6)
                r.ImGui_EndChild(ctx)
            end
            r.ImGui_PopStyleVar(ctx, 2)
            r.ImGui_EndTabItem(ctx)
        end

        restore_saved_tab = false
        r.ImGui_EndTabBar(ctx)
        end
        r.ImGui_PopFont(ctx)
    end
    
    r.ImGui_PopFont(ctx)
    r.ImGui_End(ctx)

    r.ImGui_PopStyleVar(ctx, style_pop_count)
    r.ImGui_PopStyleColor(ctx, color_pop_count)

    if open then
        r.defer(Main)
    end
end

r.defer(Main)
