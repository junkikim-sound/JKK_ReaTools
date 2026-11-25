--========================================================
-- @title JKK_Renamer
-- @author Junki Kim
-- @version 1.2.0
-- @noindex
--========================================================

local r = reaper

-- 토글 액션: 실행 중에는 액션 State가 On, 다시 실행하면 창이 닫힘 (다중 인스턴스 방지)
if reaper.set_action_options then reaper.set_action_options(1 | 4) end
reaper.atexit(function()
    if reaper.set_action_options then reaper.set_action_options(8) end
end)

-- 외부 모듈 로드
local info = debug.getinfo(1, 'S')
local script_path = info.source:match([[^@?(.*[\/])]]) or ""
local Undo = dofile(script_path .. "Modules/JKK_UndoLabels.lua")
local w_list = dofile(script_path .. "Modules/JKK_Renamer_WildcardList.lua")
local ucs_list = dofile(script_path .. "Modules/JKK_Renamer_UCSList.lua")
local sel_mgr = _G.JKK_SelectionManager or dofile(script_path .. "Modules/JKK_SelectionManager.lua")
local QueueUI = dofile(script_path .. "Modules/JKK_Renamer_QueueUI.lua")
local MiniPopup = dofile(script_path .. "Modules/JKK_MiniPopup.lua")

-- JKK_Theme.lua 안전 로드
local theme_path = script_path .. "Modules/JKK_Theme_Core.lua"
if not r.file_exists(theme_path) then
    theme_path = r.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_Theme_Core.lua"
end

local theme = r.file_exists(theme_path) and dofile(theme_path) or {}
local ApplyTheme = theme.ApplyTheme or function(ctx) return 0, 0 end
local PushButton = theme.PushButton or function(ctx, kind)
    if kind == "confirm" then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x24866FFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x2A9A80FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x1B6B58FF)
    elseif kind == "highlight" then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFFEA70FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xEFE060FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xDFD050FF)
    else
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x233C4FFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x3F586BFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x1A2E3DFF)
    end
end
local PopButton = theme.PopButton or function(ctx)
    r.ImGui_PopStyleColor(ctx, 3)
end
local GetColor = theme.GetColor or function(role)
    if role == "accent" or role == "text_accent" then return 0xE3DB8EFF end
    if role == "btn_primary" then return 0x233C4FFF end
    if role == "status" then return 0x888888FF end
    return 0xEDEDEDFF
end
local PushText = theme.PushText or function(ctx, role)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), GetColor(role))
end
local PopText = theme.PopText or function(ctx)
    r.ImGui_PopStyleColor(ctx, 1)
end

-- ReaImGui 컨텍스트 생성 및 폰트 설정
local ctx = r.ImGui_CreateContext("JKK_Renamer")
local font_large = r.ImGui_CreateFont('sans-serif', 18)
local font = r.ImGui_CreateFont('sans-serif', 16)
local font_small = r.ImGui_CreateFont('sans-serif', 14)
r.ImGui_Attach(ctx, font_large)
r.ImGui_Attach(ctx, font)
r.ImGui_Attach(ctx, font_small)

-- InputText 키보드 콜백
--  * Tab 자동완성 / 위아래 화살표 선택
--  * 미니 팝업에서 항목을 고른 뒤: (입력창이 켜진 채라면) 텍스트를 교체하고,
--    전체 선택 없이 커서를 맨 오른쪽 끝에 둔다 (caret_end 프레임 동안 유지)
local completion_callback = r.ImGui_CreateFunctionFromEEL([[
EventFlag == InputTextFlags_CallbackCompletion ? (
    tab_requested = 1;
);
EventFlag == InputTextFlags_CallbackHistory ? (
    EventKey == Key_UpArrow ? (up_requested = 1;);
    EventKey == Key_DownArrow ? (down_requested = 1;);
);
EventFlag == InputTextFlags_CallbackAlways ? (
    len = strlen(#Buf);
    replace_once ? (
        strcmp(#Buf, #replace_text) != 0 ? (
            InputTextCallback_DeleteChars(0, len);
            InputTextCallback_InsertChars(0, #replace_text);
            len = strlen(#replace_text);
        );
        replace_once = 0;
    );
    caret_end > 0 ? (
        CursorPos = len;
        SelectionStart = len;
        SelectionEnd = len;
        caret_end -= 1;
    );
);
]])

r.ImGui_Attach(ctx, completion_callback)

r.ImGui_Function_SetValue(completion_callback, "InputTextFlags_CallbackCompletion",
    r.ImGui_InputTextFlags_CallbackCompletion())
r.ImGui_Function_SetValue(completion_callback, "InputTextFlags_CallbackHistory",
    r.ImGui_InputTextFlags_CallbackHistory())
r.ImGui_Function_SetValue(completion_callback, "InputTextFlags_CallbackAlways",
    r.ImGui_InputTextFlags_CallbackAlways())
r.ImGui_Function_SetValue(completion_callback, "replace_once", 0)
r.ImGui_Function_SetValue(completion_callback, "caret_end", 0)
r.ImGui_Function_SetValue(completion_callback, "Key_UpArrow", r.ImGui_Key_UpArrow())
r.ImGui_Function_SetValue(completion_callback, "Key_DownArrow", r.ImGui_Key_DownArrow())
r.ImGui_Function_SetValue(completion_callback, "tab_requested", 0)
r.ImGui_Function_SetValue(completion_callback, "up_requested", 0)
r.ImGui_Function_SetValue(completion_callback, "down_requested", 0)

local function ShowItemTooltip(message)
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_BeginTooltip(ctx) then
        r.ImGui_Text(ctx, message)
        r.ImGui_EndTooltip(ctx)
    end
end

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

local input_buf = ""
local active_tab = r.GetExtState(ext_section, "active_tab")
if active_tab == "FindReplace" then active_tab = "Queue" end -- 1.1.x Find & Replace 탭 → Queue 탭
if active_tab ~= "Queue" then active_tab = "Rename" end
local restore_saved_tab = true

-- Queue 탭 초기화. 저장된 큐가 없으면 1.1.x Find & Replace 탭 설정을 첫 큐로 옮긴다.
QueueUI.Init({ ext_section = ext_section }, {
    find = r.GetExtState(ext_section, "find_buf"),
    replace = r.GetExtState(ext_section, "replace_buf"),
    nth_only = LoadBool("replace_nth_only", false),
    nth = tonumber(r.GetExtState(ext_section, "replace_nth")),
    remove_extension = LoadBool("remove_extension", false),
    split_camel_case = LoadBool("split_camel_case", false),
    case_mode = tonumber(r.GetExtState(ext_section, "case_mode")),
    split_underscore = LoadBool("split_underscore", false),
})

local function SaveState()
    r.SetExtState(ext_section, "use_number", use_number and "1" or "0", true)
    r.SetExtState(ext_section, "top_level_only", top_level_only and "1" or "0", true)
    r.SetExtState(ext_section, "number_start", tostring(number_start), true)
    r.SetExtState(ext_section, "active_tab", active_tab, true)
end

-- RenamerLite와 실시간 공유 옵션 동기화
local function SyncSharedSettings(num_input_active)
    local ext_num = LoadBool("use_number", false)
    local ext_top = LoadBool("top_level_only", false)
    local ext_start = tonumber(r.GetExtState(ext_section, "number_start"))

    if ext_num ~= use_number then use_number = ext_num end
    if ext_top ~= top_level_only then top_level_only = ext_top end
    if ext_start and ext_start ~= number_start and not num_input_active then
        number_start = ext_start
    end
end

local set_focus = true
local select_all_on_initial_focus = true
local initial_name_initialized = false
local last_auto_filled_name = nil
local last_input_target_signature = nil
local input_user_edited = false
local input_was_focused = false
local pending_default_name = nil
local open = true

local popup_dismissed = false
local suppress_initial_autocomplete = true
local popup_was_open = false
local popup_rect = nil

local popup_sel_idx = 1
local trigger_char = nil
local filter_str = ""

-- 미니 팝업 ($ / !) : JKK_Search와 같은 모양 (Modules/JKK_MiniPopup.lua)
local mini_popup_state = {}
local esc_dismissed_popup = false
local last_popup_key = nil
local popup_scroll_to_sel = false
-- 열 너비 기준(전체 목록의 글자들): 입력 중에도 열 위치가 흔들리지 않는다
local popup_columns = nil
local function PopupColumns()
    if popup_columns then return popup_columns end
    local function Field(list, key)
        local out = {}
        for _, item in ipairs(list) do out[#out + 1] = tostring(item[key] or "") end
        return out
    end
    popup_columns = {
        dollar = {
            { samples = Field(w_list, "insert") },
            { samples = Field(w_list, "name"), color = "muted" },
        },
        ucs = {
            { samples = Field(ucs_list, "insert"), flex = true },
            { samples = Field(ucs_list, "cat") },
            { samples = Field(ucs_list, "sub"), color = "muted" },
        },
    }
    return popup_columns
end
local function PopupPalette()
    local function Role(role, fallback)
        if theme.GetColor then
            local ok, c = pcall(theme.GetColor, role)
            if ok and type(c) == "number" then return c end
        end
        return fallback
    end
    return MiniPopup.Palette(Role("base_bg", 0x1E1E22FF), Role("control_bg", nil),
        Role("text_main", 0xEDEDEDFF), Role("accent_main", GetColor("accent")))
end

-- 팝업에서 고른 항목을 입력창에 넣는다: 뒤에 띄어쓰기 없음, 전체 선택 없이 커서는 맨 끝
--  * 입력창이 비활성 상태면 다시 포커스될 때 input_buf를 새로 읽는다
--  * 입력창이 켜진 채(Tab 자동완성)라면 콜백이 직접 텍스트를 교체한다
local function SetInputTextFromPopup(new_text)
    input_buf = new_text
    if r.ImGui_Function_SetValue_String then
        r.ImGui_Function_SetValue_String(completion_callback, "#replace_text", new_text)
        r.ImGui_Function_SetValue(completion_callback, "replace_once", 1)
    end
    r.ImGui_Function_SetValue(completion_callback, "caret_end", 3)
    popup_dismissed = true
    set_focus = true
end

local function InsertPopupItem(clean_buf, trig, item)
    if not item then return false end
    local pattern = (trig == "$") and "%$[^%s$!]*$" or "![^%s$!]*$"
    local new_text = clean_buf:gsub(pattern, function() return item.insert end, 1)
    SetInputTextFromPopup(new_text)
    return true
end

local current_mode = "None"
local mode_focus_active = false
local cached_targets = {}

local function UpdateFocusMode()
    local is_focused = r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows())
    current_mode, mode_focus_active = sel_mgr.Update(is_focused)
    return current_mode
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
    local raw_targets = sel_mgr.GetTargets()

    if not top_level_only then 
        cached_targets = raw_targets
        return cached_targets 
    end

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

    cached_targets = filtered
    return cached_targets
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

-- gsub 치환 문자열로 쓸 때 '%' 이스케이프 (이름에 %가 있어도 오류 없이)
local function Plain(text)
    return (tostring(text or ""):gsub("%%", "%%%%"))
end

-- 아이템 활성 테이크의 원본 소스 파일 이름 (경로 제외, 확장자 포함). 섹션/리버스 소스는 부모를 따라간다.
local function GetSourceFileName(item)
    local take = item and r.GetActiveTake(item)
    if not take or r.TakeIsMIDI(take) then return "" end
    local src = r.GetMediaItemTake_Source(take)
    local depth = 0
    while src and depth < 8 do
        local file_name = r.GetMediaSourceFileName(src, "")
        if file_name and file_name ~= "" then
            return file_name:match("[^/\\]+$") or file_name
        end
        src = r.GetMediaSourceParent(src)
        depth = depth + 1
    end
    return ""
end

-- Queue 탭 토큰 값: $source(확장자 제외 파일 이름), $track
local function GetTargetVars(target)
    local vars = { source = "", track = "" }
    if target.type == "Item" then
        local file_name = GetSourceFileName(target.item)
        vars.source_file = file_name
        vars.source = (file_name:gsub("%.%w+$", ""))
        if target.track then vars.track = select(2, r.GetTrackName(target.track)) or "" end
    elseif target.type == "Track" then
        vars.track = target.original_name or ""
    end
    return vars
end

local function EvaluateName(pattern, target, index, hierarchy_indices)
    local out = pattern
    if out == "" then return "" end

    if target.type == "Item" and out:find("$source", 1, true) then
        local source_name = GetSourceFileName(target.item):gsub("%.%w+$", "")
        out = out:gsub("%$source", Plain(source_name))
    else
        out = out:gsub("%$source", "")
    end

    local p_name = r.GetProjectName(0, ""):gsub("%.%w+$", "")
    out = out:gsub("%$project", Plain(p_name))
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
        out = out:gsub("%$track", Plain(t_name))
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

local function GetFormattedSelectionText(target_count)
    if target_count == 0 then
        return "No Selection"
    end
    local noun = "targets"
    if current_mode == "Item" then
        noun = (target_count == 1) and "Item" or "Items"
    elseif current_mode == "Track" then
        noun = (target_count == 1) and "Track" or "Tracks"
    elseif current_mode == "Region/Marker" or current_mode == "Region" or current_mode == "Marker" then
        local has_region, has_marker = false, false
        local targets = GetTargets()
        for _, t in ipairs(targets) do
            if t.type == "Region" then has_region = true end
            if t.type == "Marker" then has_marker = true end
        end
        
        if has_region and has_marker then
            noun = "Region/Marker"
        elseif has_region then
            noun = (target_count == 1) and "Region" or "Regions"
        elseif has_marker then
            noun = (target_count == 1) and "Marker" or "Markers"
        else
            noun = "Regions/Markers"
        end
    end

    local formatted_num = string.format("%02d", target_count)
    return string.format("Selected %s %s", formatted_num, noun)
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

local function ApplyRename(targets, hierarchy_indices)
    if input_buf == "" then return end
    r.Undo_BeginBlock()
    
    for i, target in ipairs(targets) do
        local new_name = EvaluateName(input_buf, target, i, hierarchy_indices)
        SetTargetName(target, new_name)
    end
    
    r.Undo_EndBlock(Undo.Label("renamer.batch_rename"), -1)
    r.UpdateArrange()
    input_user_edited = false
    pending_default_name = nil
end

local function BuildInputTargetSignature(targets)
    local parts = { current_mode or "None" }
    for _, target in ipairs(targets) do
        local identity = ""
        if target.type == "Item" and target.item then
            local _, guid = r.GetSetMediaItemInfo_String(target.item, "GUID", "", false)
            identity = guid or tostring(target.item)
        elseif target.type == "Track" and target.track then
            identity = r.GetTrackGUID(target.track) or tostring(target.track)
        elseif target.pm then
            identity = tostring(target.pm)
        else
            identity = tostring(target.index or "")
        end
        parts[#parts + 1] = table.concat({ target.type or "?", identity, target.original_name or "" }, ":")
    end
    return table.concat(parts, "|")
end

local num_input_active = false
local WindowChrome = dofile((debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") .. "Modules/JKK_WindowChrome.lua")

-- Queue 탭(JKK_Renamer_QueueUI)에 넘길 호스트 인터페이스
local queue_host = {
    ext_section = ext_section,
    Undo = Undo,
    PushButton = PushButton,
    PopButton = PopButton,
    GetColor = GetColor,
    targets = {},
    hierarchy_indices = nil,
    type_str = GetTargetTypeStr,
    set_name = SetTargetName,
    get_vars = GetTargetVars,
}

function queue_host.Tooltip(_, text)
    ShowItemTooltip(text)
end

-- 공유 Number(_nn) 옵션: Rename 탭/RenamerLite와 같은 번호 규칙(계층 번호 포함)
function queue_host.number_suffix(i)
    if not use_number then return nil end
    local indices = queue_host.hierarchy_indices
    return "_" .. ((indices and indices[i]) or string.format("%02d", (number_start - 1) + i))
end

function queue_host.draw_shared_options(c)
    local number_changed, number_value = r.ImGui_Checkbox(c, " Number (_nn)", use_number)
    if number_changed then
        use_number = number_value
        SaveState()
    end
    if use_number then
        r.ImGui_SameLine(c)
        r.ImGui_SetNextItemWidth(c, 45)
        local num_changed, num_value = r.ImGui_InputInt(c, "##QueueNumStart", number_start, 0)
        if r.ImGui_IsItemActive(c) then num_input_active = true end
        if num_changed then
            number_start = math.max(1, num_value)
            SaveState()
        end
    end
    r.ImGui_SameLine(c, 0, 20)
    local top_changed, top_value = r.ImGui_Checkbox(c, " Top-Level Only", top_level_only)
    if top_changed then
        top_level_only = top_value
        SaveState()
    end
end

local function Main()
    esc_dismissed_popup = false
    r.ImGui_PushFont(ctx, font, 16)
    r.ImGui_SetNextWindowSize(ctx, 840, 480, r.ImGui_Cond_FirstUseEver())
    r.ImGui_SetNextWindowSizeConstraints(ctx, 700, 320, 16384, 16384)

    local style_pop_count, color_pop_count = ApplyTheme(ctx)

    local visible, open_flag = r.ImGui_Begin(ctx, 'JKK_Renamer', open, WindowChrome.flags())
    open = open_flag

    -- Esc: 창 닫기. 단, 콤보/프리셋 등 팝업이 열려 있으면 팝업만 닫히도록 둔다.
    -- $ / ! 미니 팝업이 떠 있으면 미니 팝업만 닫는다.
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape())
        and not r.ImGui_IsPopupOpen(ctx, "", r.ImGui_PopupFlags_AnyPopupId() | r.ImGui_PopupFlags_AnyPopupLevel()) then
        if popup_was_open then
            -- InputText는 Esc를 받으면 입력 전 값으로 되돌린다: 이번 프레임의 변경은 무시한다
            esc_dismissed_popup = true
            popup_dismissed = true
            popup_was_open = false
            popup_rect = nil
            set_focus = true
            r.ImGui_Function_SetValue(completion_callback, "caret_end", 3)
        else
            open = false
        end
    end

    if visible then
        if WindowChrome.header(ctx, 'JKK Renamer', 'renamer') then open = false end
        SyncSharedSettings(num_input_active)
        UpdateFocusMode()
        
        local targets = GetTargets()
        local target_count = #targets
        local target_signature = BuildInputTargetSignature(targets)
        local first_target_name = (target_count > 0) and (targets[1].original_name or "") or ""

        if target_count > 0 then
            if not initial_name_initialized then
                input_buf = first_target_name
                last_auto_filled_name = first_target_name
                initial_name_initialized = true
                input_user_edited = false
                pending_default_name = nil
                set_focus = true
                select_all_on_initial_focus = true
            elseif target_signature ~= last_input_target_signature then
                if input_buf == (last_auto_filled_name or "") then
                    input_user_edited = false
                end
                if not input_user_edited then
                    if input_was_focused then
                        pending_default_name = first_target_name
                    else
                        input_buf = first_target_name
                        last_auto_filled_name = first_target_name
                        pending_default_name = nil
                    end
                end
            end
        end
        last_input_target_signature = target_signature
        
        local hierarchy_indices = nil
        if use_number and not top_level_only then
            hierarchy_indices = BuildHierarchyIndices(targets)
        end

        r.ImGui_PushFont(ctx, font_small, 14)
        local header_display_text = GetFormattedSelectionText(target_count)
        r.ImGui_TextColored(ctx, GetColor("accent"), header_display_text)
        r.ImGui_Spacing(ctx)
        
        num_input_active = false

        if r.ImGui_BeginTabBar(ctx, "RenamerTabs") then
        local rename_tab_flags = (restore_saved_tab and active_tab == "Rename")
            and r.ImGui_TabItemFlags_SetSelected() or 0
        if r.ImGui_BeginTabItem(ctx, "Simple", rename_tab_flags) then
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
        
        local input_rect_min_x = r.ImGui_GetCursorScreenPos(ctx)
        
        r.ImGui_Function_SetValue(completion_callback, "tab_requested", 0)
        r.ImGui_Function_SetValue(completion_callback, "up_requested", 0)
        r.ImGui_Function_SetValue(completion_callback, "down_requested", 0)

        local input_flags = r.ImGui_InputTextFlags_CallbackCompletion()
                        | r.ImGui_InputTextFlags_CallbackHistory()
                        | r.ImGui_InputTextFlags_CallbackAlways()
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
        local is_input_hovered = r.ImGui_IsItemHovered(ctx)
        -- 입력창이 꺼져 있으면 다시 켜질 때 input_buf를 새로 읽으므로 콜백 교체는 필요 없다
        if not r.ImGui_IsItemActive(ctx) then
            r.ImGui_Function_SetValue(completion_callback, "replace_once", 0)
        end
        if esc_dismissed_popup then changed = false end

        if pending_default_name and not is_focused and not input_user_edited then
            input_buf = pending_default_name
            last_auto_filled_name = pending_default_name
            pending_default_name = nil
        end
        input_was_focused = is_focused

        if changed then
            local old_buf = input_buf
            input_buf = new_buf
            input_user_edited = (new_buf ~= (last_auto_filled_name or ""))
            if input_user_edited then pending_default_name = nil end
            suppress_initial_autocomplete = false

            if new_buf:sub(-1) == "$" or new_buf:sub(-1) == "!"
                or (new_buf:len() > old_buf:len()
                and new_buf:sub(#old_buf + 1):find("[$!]")) then

                popup_dismissed = false
            end
        end

        local tab_requested = r.ImGui_Function_GetValue(completion_callback, "tab_requested") == 1
        local up_requested = r.ImGui_Function_GetValue(completion_callback, "up_requested") == 1
        local down_requested = r.ImGui_Function_GetValue(completion_callback, "down_requested") == 1
        local keyboard_popup_event = tab_requested or up_requested or down_requested

        local mouse_clicked = r.ImGui_IsMouseClicked(ctx, 0)
        if popup_was_open and mouse_clicked then
            local mx, my = r.ImGui_GetMousePos(ctx)
            local in_popup = false
            if popup_rect then
                if mx >= popup_rect.min_x and mx <= popup_rect.max_x and my >= popup_rect.min_y and my <= popup_rect.max_y then
                    in_popup = true
                end
            end
            if not is_input_hovered and not in_popup then
                popup_dismissed = true
            end
        end

        local input_rect_max_y = select(2, r.ImGui_GetItemRectMax(ctx))
        
        r.ImGui_PopFont(ctx)
        r.ImGui_PopStyleVar(ctx)
        
        r.ImGui_SameLine(ctx, 0, 8)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 5)
        r.ImGui_PushFont(ctx, font_large, 18)
        PushButton(ctx, "confirm")
        if r.ImGui_Button(ctx, "Apply", apply_btn_w, 41) then
            ApplyRename(targets, hierarchy_indices)
            open = false
        end
        PopButton(ctx)
        r.ImGui_PopFont(ctx)
        r.ImGui_PopStyleVar(ctx)

        local clean_search_buf = input_buf:gsub("[%s\t]+$", "")
        local trg_char, flt_str = clean_search_buf:match(".*([$!])([^%s$!]*)$")
        
        if trg_char == nil then
            popup_dismissed = false
        end

        local show_popup = (is_focused or keyboard_popup_event or popup_was_open)
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

        -- 필터 글자가 바뀌면 선택은 첫 항목으로 (JKK_Search와 같음)
        local popup_key = tostring(trigger_char) .. "\1" .. tostring(filter_str)
        if popup_key ~= last_popup_key then
            last_popup_key = popup_key
            popup_sel_idx = 1
        end
        popup_sel_idx = math.max(1, math.min(popup_sel_idx, #filtered > 0 and #filtered or 1))

        if show_popup then
            if up_requested then
                popup_sel_idx = math.max(1, popup_sel_idx - 1)
                popup_scroll_to_sel = true
            elseif down_requested then
                popup_sel_idx = math.min(#filtered, popup_sel_idx + 1)
                popup_scroll_to_sel = true
            end
        end

        -- Tab: 현재 선택된 항목 넣기 (예전에는 항상 첫 항목)
        if show_popup and tab_requested then
            if InsertPopupItem(clean_search_buf, trigger_char, filtered[popup_sel_idx] or filtered[1]) then
                show_popup = false
            end
        end

        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) or r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_KeypadEnter()) then
            if show_popup then
                if InsertPopupItem(clean_search_buf, trigger_char, filtered[popup_sel_idx]) then
                    show_popup = false
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
            if r.ImGui_IsItemActive(ctx) then num_input_active = true end
            if num_changed then
                number_start = math.max(1, new_num)
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
                        r.ImGui_TableNextColumn(ctx)
                        r.ImGui_TextDisabled(ctx, GetTargetTypeStr(target))
                        r.ImGui_TableNextColumn(ctx)
                        r.ImGui_Text(ctx, target.original_name or "")
                        r.ImGui_TableNextColumn(ctx)
                        r.ImGui_TextDisabled(ctx, "│")
                        r.ImGui_TableNextColumn(ctx)
                        local evaluated = EvaluateName(input_buf, target, i, hierarchy_indices)
                        r.ImGui_TextColored(ctx, GetColor("accent"),
                            evaluated == "" and (target.original_name or "") or evaluated)
                    end
                    r.ImGui_EndTable(ctx)
                end
                r.ImGui_PopFont(ctx)
            else
                r.ImGui_PushFont(ctx, font_small, 14)
                r.ImGui_TextDisabled(ctx, "No items selected.")
                r.ImGui_PopFont(ctx)
            end

            r.ImGui_Unindent(ctx, 6)
            r.ImGui_EndChild(ctx)
        end
        r.ImGui_PopStyleVar(ctx, 2)

        if show_popup then
            -- JKK_Search와 같은 모양의 미니 팝업 (Modules/JKK_MiniPopup.lua)
            local is_dollar = (trigger_char == "$")
            r.ImGui_PushFont(ctx, font_small, 14)
            local res = MiniPopup.Draw(ctx, mini_popup_state, {
                id = "Renamer Suggestions##jkk_renamer_mini",
                x = input_rect_min_x, y = input_rect_max_y, w = input_w,
                palette = PopupPalette(),
                count = #filtered,
                key = tostring(trigger_char) .. "\1" .. tostring(filter_str),
                selected = popup_sel_idx,
                ensure_visible = popup_scroll_to_sel,
                highlight = (filter_str or ""):lower(),
                -- 열 정렬: $ = 와일드카드 | 이름 ........ 설명(오른쪽 정렬)
                --          ! = CatID .......... | Category | SubCategory   (설명은 툴팁)
                columns = is_dollar and PopupColumns().dollar or PopupColumns().ucs,
                right_from = (not is_dollar) and 2 or nil,
                row = function(i)
                    local item = filtered[i]
                    if not item then return nil end
                    if is_dollar then
                        return { cols = { item.insert, item.name }, detail = item.desc }
                    end
                    return { cols = { item.insert, item.cat, item.sub }, tooltip = item.desc }
                end,
            })
            r.ImGui_PopFont(ctx)
            popup_scroll_to_sel = false
            popup_was_open = true
            if res.rect then
                popup_rect = { min_x = res.rect.x, min_y = res.rect.y,
                    max_x = res.rect.x + res.rect.w, max_y = res.rect.y + res.rect.h }
            end
            if res.clicked then
                popup_sel_idx = res.clicked
                InsertPopupItem(clean_search_buf, trigger_char, filtered[res.clicked])
            elseif res.focused and not r.ImGui_IsMouseDown(ctx, 0) then
                -- 팝업(스크롤바 등)을 클릭해 포커스가 옮겨갔으면 입력창으로 돌려준다 (커서는 맨 끝)
                set_focus = true
                r.ImGui_Function_SetValue(completion_callback, "caret_end", 3)
            end
        else
            popup_sel_idx = 1
            popup_was_open = false
            popup_rect = nil
            popup_scroll_to_sel = false
        end

        r.ImGui_EndTabItem(ctx)
        end

        local queue_tab_flags = (restore_saved_tab and active_tab == "Queue")
            and r.ImGui_TabItemFlags_SetSelected() or 0
        if r.ImGui_BeginTabItem(ctx, "Advanced", queue_tab_flags) then
            if not restore_saved_tab and active_tab ~= "Queue" then
                active_tab = "Queue"
                SaveState()
            end
            queue_host.targets = targets
            queue_host.hierarchy_indices = hierarchy_indices
            QueueUI.Draw(ctx, queue_host)
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
