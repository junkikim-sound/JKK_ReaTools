--========================================================
-- @title JKK_FolderItems_Setup
-- @author Junki Kim
-- @version 1.0.2
-- @noindex
-- JKK Folder Items Toggle 을 Mouse Modifier(더블클릭)에 등록/복원하는 설정 창
--  - 창을 여는 것만으로는 어떤 Mouse Modifier 도 바꾸지 않는다.
--  - 원래 값은 ExtState(JKK_FolderItems_Setup)에 context+flag 별로 백업, read-back 검증
--========================================================

local RPR = reaper
local TITLE = "JKK Folder Items - Setup"

if not RPR.ImGui_CreateContext then
    RPR.ShowMessageBox("ReaImGui 확장이 필요합니다.\nReaPack > ReaTeam Extensions 에서 ReaImGui를 설치해 주세요.\n\n(Create / Toggle 액션은 ReaImGui 없이도 동작합니다.)", TITLE, 0)
    return
end
if not (RPR.GetMouseModifier and RPR.SetMouseModifier) then
    RPR.ShowMessageBox("이 REAPER 버전에는 GetMouseModifier / SetMouseModifier API 가 없습니다.", TITLE, 0)
    return
end


-- 토글 액션: 실행 중에는 액션 State가 On, 다시 실행하면 창이 닫힘 (다중 인스턴스 방지)
if reaper.set_action_options then reaper.set_action_options(1 | 4) end
reaper.atexit(function()
    if reaper.set_action_options then reaper.set_action_options(8) end
end)

local script_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local installed_dir = RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/"
local function Path(filename)
    local local_path = script_dir .. "Modules/" .. filename
    if RPR.file_exists(local_path) then return local_path end
    return installed_dir .. "Modules/" .. filename
end
local root_dir = RPR.file_exists(script_dir .. "Modules/JKK_FolderItems_Core.lua") and script_dir or installed_dir

local Core = dofile(Path("JKK_FolderItems_Core.lua"))
local Theme = dofile(Path("JKK_Theme_Core.lua"))
local WindowChrome = dofile(Path("JKK_WindowChrome.lua"))


----------------------------------------------------------
-- 상태 (Modifier flag 는 0 = 보조키 없는 기본 더블클릭으로 고정)
----------------------------------------------------------
local FLAG = 0

local S = {
    consent = false,
    tinfo = Core.resolve_toggle_command(root_dir, false),
    tinfo_time = RPR.time_precise(),
    row_err = {},     -- [ctx] = 오류 메시지 (정상 동작은 표시하지 않음)
    global_err = nil,
}

local COL_WARN = 0xE8846BFF

local LABEL_W, CURRENT_W, BTN_W, ALL_W = 230, 360, 84, 140
local BTN_GAP = 6   -- Set 과 Restore 버튼 사이 추가 간격

----------------------------------------------------------
-- 동작 이름 표시 (긴 _RS... ID 대신 스크립트/액션 이름)
----------------------------------------------------------
local main_section = RPR.SectionFromUniqueID and RPR.SectionFromUniqueID(0) or 0

local function action_name(cmd)
    if not cmd or cmd == 0 then return nil end
    local t = nil
    if RPR.kbd_getTextFromCmd then
        local ok, v = pcall(RPR.kbd_getTextFromCmd, cmd, main_section)
        if ok then t = v end
    end
    if (not t or t == "") and RPR.CF_GetCommandText then
        local ok, v = pcall(RPR.CF_GetCommandText, 0, cmd)
        if ok then t = v end
    end
    if not t or t == "" then return nil end
    local script = t:match("^Script:%s*(.+)$")
    if script then return (script:gsub("%.lua$", ""):gsub("%.eel$", ""):gsub("%.py$", "")) end
    return (t:gsub("^Custom:%s*", ""))
end

local function is_toggle(raw)
    return S.tinfo.named ~= nil and Core.mm_is_toggle(raw, S.tinfo.named, S.tinfo.cmd)
end

local function describe(raw)
    if raw == nil then return "(읽을 수 없음 - 미지원)" end
    if is_toggle(raw) then
        return action_name(S.tinfo.cmd) or "JKK_FolderItems_Toggle"
    end
    local c = Core.mm_classify(raw)
    if c.type == "none" then return "No action" end
    if c.type == "command" then return action_name(c.id) or ("Action " .. c.id) end
    if c.type == "named" then
        return action_name(RPR.NamedCommandLookup(c.name)) or (c.name .. " (찾을 수 없는 액션)")
    end
    if c.type == "builtin" or c.type == "ambiguous" then return "Built-in behavior (" .. c.raw .. ")" end
    return c.raw
end

-- 원래 동작(현재 값, Toggle 이 이미 등록되었으면 백업 값)이 fallback 으로 재실행 불가한가
local function is_unsafe(raw, backup)
    local src = raw
    if raw ~= nil and is_toggle(raw) then src = backup and backup.raw end
    if src == nil then return false end
    local t = Core.mm_classify(src).type
    return not (t == "none" or t == "command" or t == "named")
end

local function read_rows()
    local rows = {}
    for _, c in ipairs(Core.CONTEXTS) do
        local raw = Core.mm_get(c.id, FLAG)
        local backup = Core.mm_read_backup(c.id, FLAG)
        rows[#rows + 1] = {
            ctx = c.id, label = c.label, raw = raw, backup = backup,
            assigned = raw ~= nil and is_toggle(raw),
            unsafe = is_unsafe(raw, backup),
        }
    end
    return rows
end

local function ensure_toggle_registered()
    if S.tinfo.named then return true end
    S.tinfo = Core.resolve_toggle_command(root_dir, true)
    S.tinfo_time = RPR.time_precise()
    return S.tinfo.named ~= nil
end

local function confirm_overwrite(old_backup, current)
    local r = RPR.ShowMessageBox(string.format(
        "이 context 에는 이전 백업이 남아 있습니다.\n\n이전 백업(원래 동작): %s\n현재 설정: %s\n\n"
        .. "현재 설정을 새 원래 동작으로 백업하고 이전 백업을 덮어쓸까요?",
        describe(old_backup.raw), describe(current)), TITLE, 4)
    return r == 6
end

local function can_set(row)
    if row.raw == nil then return false, "미지원 context" end
    if row.assigned then return false, "이미 등록됨" end
    if not S.tinfo.exists then return false, "Toggle 스크립트 없음" end
    if row.unsafe and not S.consent then return false, "아래 동의 체크 필요" end
    return true
end

local function set_one(row)
    S.global_err = nil
    local ok, m = can_set(row)
    if ok then
        if ensure_toggle_registered() then
            ok, m = Core.mm_set(row.ctx, FLAG, S.tinfo, confirm_overwrite)
        else
            ok, m = false, S.tinfo.error or "Toggle 명령 ID 미확인"
        end
    end
    S.row_err[row.ctx] = (not ok) and m or nil
end

local function set_all(rows)
    S.global_err, S.row_err = nil, {}
    -- 사전 검증: 하나라도 불가하면 아무것도 바꾸지 않는다
    local todo = {}
    for _, row in ipairs(rows) do
        if row.raw ~= nil and not row.assigned then
            local ok, why = can_set(row)
            if not ok then
                S.global_err = string.format("Set All 중단: %s - %s (변경 없음)", row.label, why)
                return
            end
            todo[#todo + 1] = row
        end
    end
    if #todo == 0 then return end
    if not ensure_toggle_registered() then
        S.global_err = S.tinfo.error or "Toggle 명령 ID 미확인"
        return
    end
    local undos = {}
    for _, row in ipairs(todo) do
        local ok, m, undo = Core.mm_set(row.ctx, FLAG, S.tinfo, confirm_overwrite)
        if not ok then
            for i = #undos, 1, -1 do Core.mm_rollback(undos[i]) end
            S.global_err = string.format("Set All 실패: %s - %s. 이번 실행에서 바꾼 행을 되돌렸습니다.", row.label, m)
            S.row_err[row.ctx] = m
            return
        end
        if undo then undos[#undos + 1] = undo end
    end
end

local function restore_one(row)
    local status, m = Core.mm_restore(row.ctx, FLAG, S.tinfo)
    S.row_err[row.ctx] = (status == "failed" or status == "skipped") and m or nil
    return status
end

local function restore_all(rows)
    S.global_err = nil
    local bad = 0
    for _, row in ipairs(rows) do
        if row.backup then
            local st = restore_one(row)
            if st == "failed" or st == "skipped" then bad = bad + 1 end
        end
    end
    if bad > 0 then S.global_err = string.format("Restore All: %d개 행을 복원하지 못했습니다 (행 아래 사유 참고).", bad) end
end

----------------------------------------------------------
-- UI
----------------------------------------------------------
local ctx = RPR.ImGui_CreateContext("JKK_FolderItems_Setup_Ctx")
local open = true
local window_flags = WindowChrome.flags()
    | RPR.ImGui_WindowFlags_AlwaysAutoResize()
    | RPR.ImGui_WindowFlags_NoScrollbar()

local function colored(color, text)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), color)
    RPR.ImGui_TextWrapped(ctx, text)
    RPR.ImGui_PopStyleColor(ctx, 1)
end

local function dim(text) colored(Theme.GetColor("status"), text) end

-- 이 창에는 툴팁을 두지 않는다 (요청에 따라 모두 제거).
local function button(label, kind, disabled, w)
    if disabled then RPR.ImGui_BeginDisabled(ctx, true) end
    if kind then Theme.PushButton(ctx, kind) end
    local clicked = RPR.ImGui_Button(ctx, label, w or 0, 0)
    if kind then Theme.PopButton(ctx) end
    if disabled then RPR.ImGui_EndDisabled(ctx) end
    return clicked and not disabled
end

-- window-local x 에서 시작해 right_x 에서 줄바꿈되는 텍스트 한 줄 (표 밖에서 그려 열 경계의 영향을 받지 않음)
local function line_at(x, right_x, color, text)
    RPR.ImGui_SetCursorPosX(ctx, x)
    RPR.ImGui_PushTextWrapPos(ctx, right_x)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), color)
    RPR.ImGui_TextWrapped(ctx, text)
    RPR.ImGui_PopStyleColor(ctx, 1)
    RPR.ImGui_PopTextWrapPos(ctx)
end

local function draw_rows(rows)
    local tflags = RPR.ImGui_TableFlags_SizingFixedFit() | RPR.ImGui_TableFlags_NoPadOuterX()
    for i, row in ipairs(rows) do
        -- 1행 (행마다 같은 고정 폭 4열 표): Context | Current | Set | Restore
        if RPR.ImGui_BeginTable(ctx, "##fi_mm_row" .. i, 4, tflags) then
            RPR.ImGui_TableSetupColumn(ctx, "label", RPR.ImGui_TableColumnFlags_WidthFixed(), LABEL_W)
            RPR.ImGui_TableSetupColumn(ctx, "current", RPR.ImGui_TableColumnFlags_WidthFixed(), CURRENT_W)
            RPR.ImGui_TableSetupColumn(ctx, "set", RPR.ImGui_TableColumnFlags_WidthFixed(), BTN_W)
            RPR.ImGui_TableSetupColumn(ctx, "restore", RPR.ImGui_TableColumnFlags_WidthFixed(), BTN_W + BTN_GAP)
            RPR.ImGui_TableNextRow(ctx)

            RPR.ImGui_TableSetColumnIndex(ctx, 0)
            RPR.ImGui_AlignTextToFramePadding(ctx)
            Theme.PushText(ctx, "accent")
            RPR.ImGui_Text(ctx, row.label)
            Theme.PopText(ctx)

            RPR.ImGui_TableSetColumnIndex(ctx, 1)
            local text_x = RPR.ImGui_GetCursorPosX(ctx)
            RPR.ImGui_AlignTextToFramePadding(ctx)
            RPR.ImGui_TextWrapped(ctx, describe(row.raw))

            local can = can_set(row)
            RPR.ImGui_TableSetColumnIndex(ctx, 2)
            if button("Set##" .. row.ctx, "confirm", not can, BTN_W) then set_one(row) end

            RPR.ImGui_TableSetColumnIndex(ctx, 3)
            local restore_x = RPR.ImGui_GetCursorPosX(ctx) + BTN_GAP
            RPR.ImGui_SetCursorPosX(ctx, restore_x)
            if button("Restore##" .. row.ctx, nil, row.backup == nil, BTN_W) then
                restore_one(row)
            end
            RPR.ImGui_EndTable(ctx)

            -- 2행: 백업 (+ 필요할 때만 경고/오류). Current 열 시작 ~ Restore 버튼 오른쪽 끝까지 한 줄
            local right_x = restore_x + BTN_W
            line_at(text_x, right_x, Theme.GetColor("status"),
                "Backup: " .. (row.backup and describe(row.backup.raw) or "none"))
            if row.unsafe then
                line_at(text_x, right_x, COL_WARN, "내장 동작이라 재실행 불가 - 일반 대상 더블클릭 동작을 잃습니다.")
            end
            if S.row_err[row.ctx] then line_at(text_x, right_x, COL_WARN, S.row_err[row.ctx]) end
            if i < #rows then RPR.ImGui_Spacing(ctx) end
        end
    end
end

local function draw()
    if not S.tinfo.named and RPR.time_precise() - S.tinfo_time > 2 then
        S.tinfo = Core.resolve_toggle_command(root_dir, false)
        S.tinfo_time = RPR.time_precise()
    end
    if not S.tinfo.exists then colored(COL_WARN, S.tinfo.error or "Toggle 스크립트를 찾을 수 없습니다.") end
    if RPR.GetToggleCommandState and RPR.GetToggleCommandState(1156) == 0 then
        colored(COL_WARN, "Item grouping 옵션이 꺼져 있습니다 - 그룹 이동이 동작하지 않을 수 있습니다 (자동 변경 안 함).")
    end

    local rows = read_rows()
    draw_rows(rows)

    local any_unsafe = false
    for _, row in ipairs(rows) do
        if row.unsafe and not row.assigned then any_unsafe = true end
    end
    if any_unsafe or S.consent then
        local rv, v = RPR.ImGui_Checkbox(ctx, "내장 더블클릭 동작을 잃는 것에 동의하고 덮어쓰기 허용##consent", S.consent)
        if rv then S.consent = v end
    end

    RPR.ImGui_Spacing(ctx)
    local spacing = select(1, RPR.ImGui_GetStyleVar(ctx, RPR.ImGui_StyleVar_ItemSpacing()))
    local total = ALL_W * 2 + spacing
    local avail = select(1, RPR.ImGui_GetContentRegionAvail(ctx))
    RPR.ImGui_SetCursorPosX(ctx, RPR.ImGui_GetCursorPosX(ctx) + math.max(0, (avail - total) / 2))
    if button("Set All", "confirm", false, ALL_W) then set_all(rows) end
    RPR.ImGui_SameLine(ctx, 0, spacing)
    if button("Restore All", nil, false, ALL_W) then restore_all(rows) end
    if S.global_err then colored(COL_WARN, S.global_err) end
end

local function Main()
    local sp, cp = Theme.ApplyTheme(ctx, 1.0)
    Theme.PushFont(ctx, 1.0, "base")
    local visible, open_flag = RPR.ImGui_Begin(ctx, TITLE, open, window_flags)
    if visible then
        if WindowChrome.header(ctx, "JKK Folder Items - Setup", "folder_items_setup") then open_flag = false end
        draw()
        -- Esc: 창 닫기 (다른 팝업이 열려 있으면 그 팝업이 먼저 닫힌다)
        if RPR.ImGui_IsWindowFocused(ctx, RPR.ImGui_FocusedFlags_RootAndChildWindows())
            and RPR.ImGui_IsKeyPressed(ctx, RPR.ImGui_Key_Escape(), false)
            and not RPR.ImGui_IsPopupOpen(ctx, "", RPR.ImGui_PopupFlags_AnyPopupId() | RPR.ImGui_PopupFlags_AnyPopupLevel()) then
            open_flag = false
        end
    end
    RPR.ImGui_End(ctx)
    Theme.PopFont(ctx)
    RPR.ImGui_PopStyleVar(ctx, sp)
    RPR.ImGui_PopStyleColor(ctx, cp)

    open = open_flag
    if open then
        RPR.defer(Main)
    elseif RPR.ImGui_DestroyContext then
        RPR.ImGui_DestroyContext(ctx)
    end
end

RPR.defer(Main)
