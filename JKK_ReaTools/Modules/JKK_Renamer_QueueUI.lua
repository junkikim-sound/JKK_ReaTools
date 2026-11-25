--========================================================
-- @title JKK_Renamer_QueueUI
-- @author Junki Kim
-- @noindex
--========================================================
-- JKK_Renamer "Queue" 탭.
-- 왼쪽: 단계 목록(추가/순서/복제/삭제/on-off, 드래그 정렬) / 오른쪽: 선택 단계 편집기
-- 아래: 단계별 중간 결과 미리보기 → Apply 시 최종 결과를 Undo 1회로 적용.
-- 변환 로직은 JKK_Renamer_Engine(순수 함수)에 있고, 이 모듈은 UI와 상태 저장만 담당한다.
--
-- 호스트(H) 인터페이스 (JKK_Renamer.lua가 채움)
--   H.ext_section, H.Undo, H.PushButton/PopButton, H.GetColor, H.Tooltip(ctx, text)
--   H.targets                       : 현재 대상 목록
--   H.number_suffix(i) -> str|nil   : 공유 Number(_nn) 옵션 접미사
--   H.get_vars(target) -> { source=, track= }
--   H.type_str(target) -> str
--   H.set_name(target, new_name)
--   H.draw_shared_options(ctx)      : Number(_nn) / Top-Level Only 체크박스 (Rename 탭과 공유)

local r = reaper
local script_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local E = dofile(script_dir .. "JKK_Renamer_Engine.lua")

local Q = {}

local KEY_STEPS = "queue_steps"
local KEY_KEEP_EXT = "queue_keep_ext"
local KEY_PRESETS = "queue_presets"
local DRAG_TYPE = "JKK_RENAMER_QSTEP"
local LABEL_W = 86
local ERROR_COLOR = 0xE06C6CFF

local steps = {}
local selected = 0
local keep_ext = true
local presets = {}
local preset_name_buf = ""
local dirty = false
local section = "JKK_SmartBatchRenamer"

local function MarkDirty() dirty = true end

local function Save()
    r.SetExtState(section, KEY_STEPS, E.Serialize(steps), true)
    r.SetExtState(section, KEY_KEEP_EXT, keep_ext and "1" or "0", true)
    dirty = false
end

local function SavePresets()
    r.SetExtState(section, KEY_PRESETS, E.SerializePresets(presets), true)
end

-- 기존 Find & Replace 탭 설정을 첫 Queue로 옮긴다
local function MigrateLegacy(legacy)
    local list = {}
    legacy = legacy or {}
    list[#list + 1] = E.NewStep("replace", {
        find = legacy.find or "",
        with = legacy.replace or "",
        occ = legacy.nth_only and "nth" or "all",
        n = math.max(1, tonumber(legacy.nth) or 1),
    })
    if legacy.remove_extension then list[#list + 1] = E.NewStep("ext", { mode = "remove" }) end
    if legacy.split_camel_case then list[#list + 1] = E.NewStep("camel") end
    local case_modes = { "lower", "upper", "title", "title_keep" }
    local cm = case_modes[tonumber(legacy.case_mode) or 0]
    if cm then
        list[#list + 1] = E.NewStep("case", { mode = cm, split_underscore = legacy.split_underscore and true or false })
    end
    return list
end

function Q.Init(H, legacy)
    section = H.ext_section or section
    local saved = E.Deserialize(r.GetExtState(section, KEY_STEPS))
    steps = saved or MigrateLegacy(legacy)
    selected = (#steps > 0) and 1 or 0
    keep_ext = r.GetExtState(section, KEY_KEEP_EXT) ~= "0"
    presets = E.DeserializePresets(r.GetExtState(section, KEY_PRESETS))
end

---------------------------------------------------------
-- 단계 조작
---------------------------------------------------------
local function AddStep(op)
    local pos = (selected >= 1 and selected <= #steps) and (selected + 1) or (#steps + 1)
    table.insert(steps, pos, E.NewStep(op))
    selected = pos
    MarkDirty()
end

local function MoveStep(from, to)
    if from == to or not steps[from] or to < 1 or to > #steps then return end
    local st = table.remove(steps, from)
    table.insert(steps, to, st)
    selected = to
    MarkDirty()
end

local function DuplicateStep()
    local st = steps[selected]
    if not st then return end
    table.insert(steps, selected + 1, E.CopyStep(st))
    selected = selected + 1
    MarkDirty()
end

local function DeleteStep()
    if not steps[selected] then return end
    table.remove(steps, selected)
    if selected > #steps then selected = #steps end
    MarkDirty()
end

---------------------------------------------------------
-- 편집 위젯
---------------------------------------------------------
local function Label(ctx, text)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, text)
    r.ImGui_SameLine(ctx, LABEL_W)
end

local function TextField(ctx, st, key, id, hint, width)
    r.ImGui_SetNextItemWidth(ctx, width or -1)
    local changed, v = r.ImGui_InputTextWithHint(ctx, id, hint or "", st[key] or "")
    if changed then
        st[key] = v
        MarkDirty()
    end
end

-- 항목 전체가 스크롤 없이 보이고(HeightLargest), 펼친 목록과 닫힌 상태의 표시값이 모두 가운데 정렬되는 콤보.
-- 선택이 바뀌면 새 인덱스(0-based), 아니면 nil 반환.
local function CenteredCombo(ctx, id, current_idx, labels, width)
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local frame_h = r.ImGui_GetFrameHeight(ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local preview = labels[current_idx + 1] or ""
    local new_idx = nil

    r.ImGui_SetNextItemWidth(ctx, width)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_SelectableTextAlign(), 0.5, 0.5)
    if r.ImGui_BeginCombo(ctx, id, "", r.ImGui_ComboFlags_HeightLargest()) then
        for i, label in ipairs(labels) do
            local is_current = (i - 1 == current_idx)
            if r.ImGui_Selectable(ctx, label, is_current) then new_idx = i - 1 end
            if is_current then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    r.ImGui_PopStyleVar(ctx, 1)

    -- 닫힌 콤보의 표시값을 화살표 영역을 뺀 프레임 가운데에 직접 그린다
    local text_w, text_h = r.ImGui_CalcTextSize(ctx, preview)
    local inner_w = width - frame_h
    r.ImGui_DrawList_AddText(draw_list,
        x + math.max(0, (inner_w - text_w) * 0.5),
        y + (frame_h - text_h) * 0.5,
        r.ImGui_GetColor(ctx, r.ImGui_Col_Text()), preview)

    if new_idx == current_idx then return nil end
    return new_idx
end

local function ComboField(ctx, st, key, id, values, labels, width)
    local idx = 0
    for i, v in ipairs(values) do
        if v == st[key] then idx = i - 1 end
    end
    local ni = CenteredCombo(ctx, id, idx, labels, width)
    if ni and values[ni + 1] ~= nil then
        st[key] = values[ni + 1]
        MarkDirty()
    end
end

local function IntField(ctx, st, key, id, width, min_v, max_v)
    r.ImGui_SetNextItemWidth(ctx, width)
    local changed, v = r.ImGui_InputInt(ctx, id, math.floor(tonumber(st[key]) or 0), 1)
    if changed then
        if min_v and v < min_v then v = min_v end
        if max_v and v > max_v then v = max_v end
        st[key] = v
        MarkDirty()
    end
end

local function CheckField(ctx, st, key, label)
    local changed, v = r.ImGui_Checkbox(ctx, label, st[key] and true or false)
    if changed then
        st[key] = v
        MarkDirty()
    end
end

local INT_W = 92
local OCC_FROM_VALUES = { false, true }
local OCC_FROM_LABELS = { "from start", "from end" }

local function NthRow(ctx, H, st, key, label)
    Label(ctx, label)
    IntField(ctx, st, key, "##q_nth_" .. key, INT_W, 1)
    r.ImGui_SameLine(ctx, 0, 6)
    ComboField(ctx, st, "from_end", "##q_from_end", OCC_FROM_VALUES, OCC_FROM_LABELS, 104)
    H.Tooltip(ctx, "Which occurrence to use: 1 = first, counted from the start or the end.")
end

local EDITORS = {}

EDITORS.replace = function(ctx, H, st)
    Label(ctx, "Find")
    TextField(ctx, st, "find", "##q_find", "Text to find...")
    Label(ctx, "Replace")
    TextField(ctx, st, "with", "##q_with", "Replace with... ($source, $track)")
    Label(ctx, "Match")
    ComboField(ctx, st, "occ", "##q_occ", { "all", "nth" }, { "All occurrences", "Nth occurrence only" }, 160)
    if st.occ == "nth" then
        r.ImGui_SameLine(ctx, 0, 6)
        IntField(ctx, st, "n", "##q_n", INT_W, 1)
        r.ImGui_SameLine(ctx, 0, 6)
        ComboField(ctx, st, "from_end", "##q_from_end", OCC_FROM_VALUES, OCC_FROM_LABELS, 104)
    end
    r.ImGui_SetCursorPosX(ctx, LABEL_W)
    r.ImGui_BeginDisabled(ctx, st.pattern)
    CheckField(ctx, st, "ignore_case", "Ignore case")
    r.ImGui_EndDisabled(ctx)
    r.ImGui_SameLine(ctx, 0, 12)
    CheckField(ctx, st, "whole_word", "Whole word")
    r.ImGui_SameLine(ctx, 0, 12)
    CheckField(ctx, st, "pattern", "Lua pattern")
    H.Tooltip(ctx, "Treat Find as a Lua pattern (%d = digit, %s = space, . = any).\nUse %1..%9 in Replace for captures.")
end

EDITORS.insert = function(ctx, H, st)
    Label(ctx, "Text")
    TextField(ctx, st, "text", "##q_text", "Text to insert ($source, $track)")
    Label(ctx, "Position")
    ComboField(ctx, st, "where", "##q_where", { "start", "end", "before", "after" },
        { "From start", "From end", "Before text", "After text" }, 130)
    local anchored = (st.where == "before" or st.where == "after")
    if not anchored then
        r.ImGui_SameLine(ctx, 0, 6)
        IntField(ctx, st, "n", "##q_offset", INT_W, 0)
        H.Tooltip(ctx, "Offset from the edge. 0 = very start / end.")
        r.ImGui_SameLine(ctx, 0, 6)
        ComboField(ctx, st, "unit", "##q_unit", { "char", "word" }, { "chars", "words" }, 80)
    else
        Label(ctx, "Anchor")
        TextField(ctx, st, "find", "##q_anchor", "Text or word to insert around...")
        NthRow(ctx, H, st, "nth", "Match")
    end
    r.ImGui_SetCursorPosX(ctx, LABEL_W)
    if anchored then
        CheckField(ctx, st, "ignore_case", "Ignore case")
        r.ImGui_SameLine(ctx, 0, 12)
        CheckField(ctx, st, "whole_word", "Whole word")
        r.ImGui_SameLine(ctx, 0, 12)
    end
    r.ImGui_BeginDisabled(ctx, not anchored and st.unit ~= "word")
    CheckField(ctx, st, "auto_sep", "Auto separator")
    r.ImGui_EndDisabled(ctx)
    H.Tooltip(ctx, "Keeps the inserted text apart from the neighbouring word\nusing the name's own separator (space, _ or -).")
end

EDITORS.remove = function(ctx, H, st)
    Label(ctx, "Remove")
    ComboField(ctx, st, "what", "##q_what", { "digits", "non_digits", "trailing_num", "first", "last" },
        { "All digits", "Everything except digits", "Trailing number (_01)", "First N characters", "Last N characters" }, 220)
    if st.what == "first" or st.what == "last" then
        Label(ctx, "Count")
        IntField(ctx, st, "n", "##q_count", INT_W, 0)
    end
end

EDITORS.case = function(ctx, H, st)
    Label(ctx, "Case")
    ComboField(ctx, st, "mode", "##q_case", { "lower", "upper", "title", "title_keep", "sentence" },
        { "lowercase", "UPPERCASE", "Title Case", "Title Case (Keep ALL CAPS)", "Sentence case" }, 220)
    if st.mode == "title" or st.mode == "title_keep" then
        r.ImGui_SetCursorPosX(ctx, LABEL_W)
        CheckField(ctx, st, "split_underscore", "Split _ words")
        H.Tooltip(ctx, "Treat underscores as word separators when applying Title Case.")
    end
end

EDITORS.camel = function(ctx, H, st)
    Label(ctx, "Separator")
    TextField(ctx, st, "sep", "##q_camel_sep", "", 60)
    r.ImGui_SetCursorPosX(ctx, LABEL_W)
    r.ImGui_TextDisabled(ctx, "MetalImpact -> Metal Impact")
end

EDITORS.cleanup = function(ctx, H, st)
    r.ImGui_SetCursorPosX(ctx, LABEL_W)
    CheckField(ctx, st, "collapse_spaces", "Collapse repeated spaces")
    r.ImGui_SetCursorPosX(ctx, LABEL_W)
    CheckField(ctx, st, "collapse_seps", "Collapse repeated _ - .")
    r.ImGui_SetCursorPosX(ctx, LABEL_W)
    CheckField(ctx, st, "trim_edges", "Trim spaces / separators at both ends")
end

EDITORS.number = function(ctx, H, st)
    Label(ctx, "Position")
    ComboField(ctx, st, "position", "##q_num_pos", { "suffix", "prefix" }, { "Suffix", "Prefix" }, 130)
    Label(ctx, "Start")
    IntField(ctx, st, "start", "##q_num_start", INT_W)
    r.ImGui_SameLine(ctx, 0, 12)
    r.ImGui_Text(ctx, "Step")
    r.ImGui_SameLine(ctx, 0, 6)
    IntField(ctx, st, "step", "##q_num_step", INT_W)
    Label(ctx, "Digits")
    IntField(ctx, st, "pad", "##q_num_pad", INT_W, 1, 8)
    r.ImGui_SameLine(ctx, 0, 12)
    r.ImGui_Text(ctx, "Separator")
    r.ImGui_SameLine(ctx, 0, 6)
    TextField(ctx, st, "sep", "##q_num_sep", "", 60)
end

EDITORS.set = function(ctx, H, st)
    Label(ctx, "From")
    ComboField(ctx, st, "from", "##q_set_from", { "source", "track", "text" },
        { "Take source file name", "Track name", "Text" }, 220)
    if st.from == "text" then
        Label(ctx, "Text")
        TextField(ctx, st, "text", "##q_set_text", "$source = file name without extension")
    elseif st.from == "source" then
        r.ImGui_SetCursorPosX(ctx, LABEL_W)
        r.ImGui_TextDisabled(ctx, "Items only. Uses the active take's file name.")
    end
end

EDITORS.ext = function(ctx, H, st)
    Label(ctx, "Extension")
    ComboField(ctx, st, "mode", "##q_ext_mode", { "remove", "lower", "upper", "set" },
        { "Remove", "lowercase", "UPPERCASE", "Change to" }, 130)
    if st.mode == "set" then
        r.ImGui_SameLine(ctx, 0, 6)
        TextField(ctx, st, "text", "##q_ext_text", "wav", 80)
    end
end

---------------------------------------------------------
-- 레이아웃 조각
---------------------------------------------------------
local function OpLabels()
    local labels = {}
    for i, op in ipairs(E.OP_ORDER) do labels[i] = E.OpLabel(op) end
    return labels
end

local function DrawStepList(ctx, H, w, h, errors_by_step)
    if not r.ImGui_BeginChild(ctx, "##q_steps", w, h, r.ImGui_ChildFlags_Borders()) then return end

    local fh = r.ImGui_GetFrameHeight(ctx)
    local text_btn_w = 52
    if r.ImGui_Button(ctx, "+ Add", text_btn_w, fh) then r.ImGui_OpenPopup(ctx, "##q_add_menu") end
    if r.ImGui_BeginPopup(ctx, "##q_add_menu") then
        for _, op in ipairs(E.OP_ORDER) do
            if r.ImGui_Selectable(ctx, E.OpLabel(op)) then AddStep(op) end
        end
        r.ImGui_EndPopup(ctx)
    end

    r.ImGui_SameLine(ctx, 0, 4)
    r.ImGui_BeginDisabled(ctx, selected <= 1)
    if r.ImGui_ArrowButton(ctx, "##q_up", r.ImGui_Dir_Up()) then MoveStep(selected, selected - 1) end
    r.ImGui_EndDisabled(ctx)
    r.ImGui_SameLine(ctx, 0, 4)
    r.ImGui_BeginDisabled(ctx, selected < 1 or selected >= #steps)
    if r.ImGui_ArrowButton(ctx, "##q_down", r.ImGui_Dir_Down()) then MoveStep(selected, selected + 1) end
    r.ImGui_EndDisabled(ctx)
    r.ImGui_SameLine(ctx, 0, 4)
    r.ImGui_BeginDisabled(ctx, steps[selected] == nil)
    if r.ImGui_Button(ctx, "Dup", text_btn_w, fh) then DuplicateStep() end
    H.Tooltip(ctx, "Duplicate the selected step")
    r.ImGui_SameLine(ctx, 0, 4)
    if r.ImGui_Button(ctx, "✕##q_delete", fh, fh) then DeleteStep() end
    H.Tooltip(ctx, "Delete the selected step")
    r.ImGui_EndDisabled(ctx)

    r.ImGui_Separator(ctx)

    if r.ImGui_BeginChild(ctx, "##q_step_rows", 0, 0) then
        if #steps == 0 then
            r.ImGui_TextDisabled(ctx, "No steps. Click + Add.")
        end
        local pending_move = nil
        local disabled_col = r.ImGui_GetStyleColor(ctx, r.ImGui_Col_TextDisabled())
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_SelectableTextAlign(), 0, 0.5)
        for i, st in ipairs(steps) do
            r.ImGui_PushID(ctx, i)
            local on_changed, on = r.ImGui_Checkbox(ctx, "##on", st.on)
            if on_changed then
                st.on = on
                MarkDirty()
            end
            H.Tooltip(ctx, "Enable / disable this step")
            r.ImGui_SameLine(ctx, 0, 4)

            local err = errors_by_step[i]
            local color = err and ERROR_COLOR or (not st.on and disabled_col) or nil
            if color then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), color) end
            local label = string.format("%d  %s%s", i, E.Describe(st), err and "  (!)" or "")
            if r.ImGui_Selectable(ctx, label .. "##row", selected == i, 0, 0, fh) then selected = i end
            if color then r.ImGui_PopStyleColor(ctx, 1) end
            if err then H.Tooltip(ctx, err) end

            if r.ImGui_BeginDragDropSource(ctx) then
                r.ImGui_SetDragDropPayload(ctx, DRAG_TYPE, tostring(i))
                r.ImGui_Text(ctx, E.Describe(st))
                r.ImGui_EndDragDropSource(ctx)
            end
            if r.ImGui_BeginDragDropTarget(ctx) then
                local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, DRAG_TYPE)
                if ok then pending_move = { from = tonumber(payload), to = i } end
                r.ImGui_EndDragDropTarget(ctx)
            end
            r.ImGui_PopID(ctx)
        end
        r.ImGui_PopStyleVar(ctx, 1)
        if pending_move and pending_move.from then MoveStep(pending_move.from, pending_move.to) end
        r.ImGui_EndChild(ctx)
    end
    r.ImGui_EndChild(ctx)
end

local function DrawEditor(ctx, H, w, h)
    if not r.ImGui_BeginChild(ctx, "##q_editor", w, h, r.ImGui_ChildFlags_Borders()) then return end
    local st = steps[selected]
    if not st then
        r.ImGui_TextDisabled(ctx, "Select a step, or click + Add to start a queue.")
    else
        Label(ctx, "Step " .. selected)
        local idx = 0
        for i, op in ipairs(E.OP_ORDER) do
            if op == st.op then idx = i - 1 end
        end
        local ni = CenteredCombo(ctx, "##q_op", idx, OpLabels(), 160)
        if ni and E.OP_ORDER[ni + 1] and E.OP_ORDER[ni + 1] ~= st.op then
            local was_on = st.on
            st = E.NewStep(E.OP_ORDER[ni + 1])
            st.on = was_on
            steps[selected] = st
            MarkDirty()
        end
        if not st.on then
            r.ImGui_SameLine(ctx, 0, 10)
            r.ImGui_TextDisabled(ctx, "(disabled)")
        end

        local editor = EDITORS[st.op]
        if editor then
            r.ImGui_PushID(ctx, selected)
            editor(ctx, H, st)
            r.ImGui_PopID(ctx)
        end
    end
    r.ImGui_EndChild(ctx)
end

local function ApplyQueue(H, targets, results)
    local pending = {}
    for i, target in ipairs(targets) do
        local new_name = results[i] and results[i].final
        if new_name and new_name ~= (target.original_name or "") then
            pending[#pending + 1] = { target = target, name = new_name }
        end
    end
    if #pending == 0 then return end
    r.Undo_BeginBlock2(0)
    r.PreventUIRefresh(1)
    for _, edit in ipairs(pending) do H.set_name(edit.target, edit.name) end
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock2(0, H.Undo.Label("renamer.queue_apply"), -1)
    r.UpdateArrange()
end

local function DrawPresetsPopup(ctx)
    if not r.ImGui_BeginPopup(ctx, "##q_presets") then return end
    r.ImGui_TextDisabled(ctx, "Save current queue")
    r.ImGui_SetNextItemWidth(ctx, 200)
    local changed, v = r.ImGui_InputTextWithHint(ctx, "##q_preset_name", "Preset name", preset_name_buf)
    if changed then preset_name_buf = v end
    r.ImGui_SameLine(ctx, 0, 6)
    local name = preset_name_buf:match("^%s*(.-)%s*$")
    r.ImGui_BeginDisabled(ctx, name == "")
    if r.ImGui_Button(ctx, "Save", 52) then
        local data = E.Serialize(steps)
        local replaced = false
        for _, p in ipairs(presets) do
            if p.name == name then
                p.data = data
                replaced = true
            end
        end
        if not replaced then presets[#presets + 1] = { name = name, data = data } end
        SavePresets()
        preset_name_buf = ""
    end
    r.ImGui_EndDisabled(ctx)

    r.ImGui_Separator(ctx)
    if #presets == 0 then r.ImGui_TextDisabled(ctx, "No saved presets.") end
    local remove_idx = nil
    for i, p in ipairs(presets) do
        r.ImGui_PushID(ctx, i)
        if r.ImGui_Selectable(ctx, p.name, false, 0, 230) then
            local loaded = E.Deserialize(p.data)
            if loaded then
                steps = loaded
                selected = (#steps > 0) and 1 or 0
                MarkDirty()
            end
        end
        r.ImGui_SameLine(ctx, 0, 6)
        if r.ImGui_SmallButton(ctx, "✕") then remove_idx = i end
        r.ImGui_PopID(ctx)
    end
    if remove_idx then
        table.remove(presets, remove_idx)
        SavePresets()
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_Selectable(ctx, "Clear queue") then
        steps = {}
        selected = 0
        MarkDirty()
    end
    r.ImGui_EndPopup(ctx)
end

local function DrawPreview(ctx, H, targets, results)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 8)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 6.0)
    local pw, ph = r.ImGui_GetContentRegionAvail(ctx)
    if r.ImGui_BeginChild(ctx, "##q_preview", pw, ph, r.ImGui_ChildFlags_Borders()) then
        r.ImGui_Indent(ctx, 6)
        r.ImGui_Spacing(ctx)
        if #targets == 0 then
            r.ImGui_TextDisabled(ctx, "No items selected.")
        else
            -- 중간 단계 열: 활성 단계 중 마지막을 제외(마지막 결과는 After 열)
            local mid = {}
            for i, st in ipairs(steps) do
                if st.on and E.OPS[st.op] then mid[#mid + 1] = i end
            end
            local last_step = mid[#mid]
            mid[#mid] = nil

            local type_w, div_w, name_min_w = 100, 18, 170
            local name_cols = #mid + 2
            local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx))
            local scroll_x = (type_w + div_w + name_cols * name_min_w) > avail_w
            local flags = r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_ScrollY()
            if scroll_x then flags = flags | r.ImGui_TableFlags_ScrollX() end
            local name_flag = scroll_x and r.ImGui_TableColumnFlags_WidthFixed() or r.ImGui_TableColumnFlags_WidthStretch()
            local name_w = scroll_x and name_min_w or 0

            if r.ImGui_BeginTable(ctx, "##q_preview_table_" .. name_cols, 3 + #mid + 1, flags) then
                r.ImGui_TableSetupScrollFreeze(ctx, 3, 1)
                r.ImGui_TableSetupColumn(ctx, "Type", r.ImGui_TableColumnFlags_WidthFixed(), type_w)
                r.ImGui_TableSetupColumn(ctx, "Before", name_flag, name_w)
                r.ImGui_TableSetupColumn(ctx, "##div", r.ImGui_TableColumnFlags_WidthFixed(), div_w)
                for _, si in ipairs(mid) do
                    r.ImGui_TableSetupColumn(ctx, "##step" .. si, name_flag, name_w)
                end
                r.ImGui_TableSetupColumn(ctx, "After", name_flag, name_w)

                -- 헤더 (단계 열은 번호 + 종류, 클릭하면 해당 단계 선택)
                r.ImGui_TableNextRow(ctx, r.ImGui_TableRowFlags_Headers())
                r.ImGui_TableSetColumnIndex(ctx, 0); r.ImGui_TableHeader(ctx, "Type")
                r.ImGui_TableSetColumnIndex(ctx, 1); r.ImGui_TableHeader(ctx, "Before")
                r.ImGui_TableSetColumnIndex(ctx, 2); r.ImGui_TableHeader(ctx, "##div")
                for c, si in ipairs(mid) do
                    r.ImGui_TableSetColumnIndex(ctx, 2 + c)
                    r.ImGui_TableHeader(ctx, string.format("%d. %s##h%d", si, E.OpLabel(steps[si].op), si))
                    if r.ImGui_IsItemClicked(ctx) then selected = si end
                    H.Tooltip(ctx, E.Describe(steps[si]))
                end
                r.ImGui_TableSetColumnIndex(ctx, 3 + #mid)
                r.ImGui_TableHeader(ctx, last_step and string.format("After (%d. %s)##hafter", last_step, E.OpLabel(steps[last_step].op)) or "After")
                if last_step then
                    if r.ImGui_IsItemClicked(ctx) then selected = last_step end
                    H.Tooltip(ctx, E.Describe(steps[last_step]))
                end

                local accent = H.GetColor("accent")
                local sel_bg = (H.GetColor("btn_primary") & 0xFFFFFF00) | 0x90
                for i, target in ipairs(targets) do
                    local res = results[i]
                    r.ImGui_TableNextRow(ctx)
                    r.ImGui_TableNextColumn(ctx)
                    r.ImGui_TextDisabled(ctx, H.type_str(target))
                    r.ImGui_TableNextColumn(ctx)
                    r.ImGui_Text(ctx, target.original_name or "")
                    r.ImGui_TableNextColumn(ctx)
                    r.ImGui_TextDisabled(ctx, "│")
                    local prev = target.original_name or ""
                    for _, si in ipairs(mid) do
                        r.ImGui_TableNextColumn(ctx)
                        if si == selected then r.ImGui_TableSetBgColor(ctx, r.ImGui_TableBgTarget_CellBg(), sel_bg) end
                        local stage = res.stages[si] or prev
                        if res.errors[si] then
                            r.ImGui_TextColored(ctx, ERROR_COLOR, stage)
                        elseif stage ~= prev then
                            r.ImGui_TextColored(ctx, accent, stage)
                        else
                            r.ImGui_TextDisabled(ctx, stage)
                        end
                        prev = stage
                    end
                    r.ImGui_TableNextColumn(ctx)
                    if last_step and last_step == selected then
                        r.ImGui_TableSetBgColor(ctx, r.ImGui_TableBgTarget_CellBg(), sel_bg)
                    end
                    if res.final ~= (target.original_name or "") then
                        r.ImGui_TextColored(ctx, accent, res.final)
                    else
                        r.ImGui_TextDisabled(ctx, res.final)
                    end
                end
                r.ImGui_EndTable(ctx)
            end
        end
        r.ImGui_Unindent(ctx, 6)
        r.ImGui_EndChild(ctx)
    end
    r.ImGui_PopStyleVar(ctx, 2)
end

---------------------------------------------------------
-- 메인 Draw
---------------------------------------------------------
function Q.Draw(ctx, H)
    local targets = H.targets or {}
    local count = #targets

    -- 모든 대상에 대해 큐 실행 (미리보기 / 적용 / 오류 표시 공용)
    local results, errors_by_step, change_count = {}, {}, 0
    for i, target in ipairs(targets) do
        local final, stages, errors = E.Run(target.original_name or "", steps,
            { keep_ext = keep_ext, suffix = H.number_suffix(i) },
            { index = i, count = count, vars = H.get_vars(target) })
        results[i] = { final = final, stages = stages, errors = errors }
        for si, err in pairs(errors) do errors_by_step[si] = errors_by_step[si] or err end
        if final ~= (target.original_name or "") then change_count = change_count + 1 end
    end

    r.ImGui_Spacing(ctx)
    local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    local fhs = r.ImGui_GetFrameHeightWithSpacing(ctx)
    local top_h = math.floor(fhs * 6 + 16)
    top_h = math.max(math.floor(fhs * 3), math.min(top_h, avail_h - fhs * 4))
    local list_w = math.max(260, math.floor(avail_w * 0.38))
    local gap = 8

    DrawStepList(ctx, H, list_w, top_h, errors_by_step)
    r.ImGui_SameLine(ctx, 0, gap)
    DrawEditor(ctx, H, avail_w - list_w - gap, top_h)

    -- 옵션 줄: Keep extension / 공유 Number·Top-Level / Presets / Apply
    r.ImGui_Spacing(ctx)
    local row_x = r.ImGui_GetCursorPosX(ctx)
    local ke_changed, ke = r.ImGui_Checkbox(ctx, "Keep extension", keep_ext)
    if ke_changed then
        keep_ext = ke
        MarkDirty()
    end
    H.Tooltip(ctx, "Steps work on the name without its file extension (.wav etc.),\nthen the extension is put back.")
    r.ImGui_SameLine(ctx, 0, 20)
    H.draw_shared_options(ctx)

    local presets_w, apply_w = 80, 90
    local fh = r.ImGui_GetFrameHeight(ctx)
    r.ImGui_SameLine(ctx, 0, 0)
    local right_x = row_x + avail_w - presets_w - gap - apply_w
    r.ImGui_SetCursorPosX(ctx, math.max(r.ImGui_GetCursorPosX(ctx) + gap, right_x))
    if r.ImGui_Button(ctx, "Presets", presets_w, fh) then r.ImGui_OpenPopup(ctx, "##q_presets") end
    DrawPresetsPopup(ctx)
    r.ImGui_SameLine(ctx, 0, gap)
    r.ImGui_BeginDisabled(ctx, change_count == 0)
    H.PushButton(ctx, "confirm")
    local apply_clicked = r.ImGui_Button(ctx, "Apply##q_apply", apply_w, fh)
    H.PopButton(ctx)
    r.ImGui_EndDisabled(ctx)
    if r.ImGui_IsItemHovered(ctx, r.ImGui_HoveredFlags_AllowWhenDisabled()) then
        r.ImGui_SetTooltip(ctx, string.format("Apply all enabled steps in one undo (Ctrl+Enter)\n%d of %d names will change", change_count, count))
    end

    local ctrl_enter = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl())
        and (r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) or r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_KeypadEnter()))
    if (apply_clicked or ctrl_enter) and change_count > 0 then
        ApplyQueue(H, targets, results)
    end

    r.ImGui_Spacing(ctx)
    DrawPreview(ctx, H, targets, results)

    if dirty then Save() end
end

return Q
