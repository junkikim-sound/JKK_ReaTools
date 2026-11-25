--========================================================
-- @title JKK_ReaTools_Launcher
-- @author Junki Kim
-- @noindex
--========================================================
-- JKK_ReaTools 상단 바 오른쪽의 "JKK 윈도우 스크립트 실행" 버튼 줄.
--  * 아이콘: Modules/Icons/JKK_ReaTools/<icon>.png (흰색 + 투명 배경 권장, 테마 색으로 틴트)
--    파일이 없으면 글자(R, V ...)로 표시. 2초마다 다시 확인하므로 실행 중에 넣어도 바로 나타난다.
--  * 스크립트가 실행 중이면(액션 토글 On) 버튼이 강조된다. 다시 누르면 창이 닫힌다(토글 액션).
--  * 맨 오른쪽 설정 버튼: 버튼별 보이기/숨기기 체크박스 팝업.
--  * 설치되지 않은(파일이 없는) 스크립트의 버튼은 자동으로 숨겨진다.
--========================================================

local RPR = reaper
local M = {}

local EXT_SECTION = "JKK_ReaTools"
local EXT_HIDDEN  = "launcher_hidden"
local EXT_CMD     = "launcher_cmd_"   -- + id : 등록된 액션의 named command (_RS...)

-- 표시 순서. path는 Scripts/JKK_ReaTools/ 기준.
M.ITEMS = {
    { id = "search",       label = "S",  name = "JKK Search",           path = "JKK_ReaTools/JKK_Search.lua",            icon = "Launcher_Search" },
    { id = "renamer",      label = "Rn", name = "JKK Renamer",          path = "JKK_ReaTools/JKK_Renamer.lua",           icon = "Launcher_Renamer" },
    { id = "renderer",     label = "R",  name = "JKK Renderer",         path = "JKK_ReaTools/JKK_Renderer.lua",          icon = "Launcher_Renderer" },
    { id = "loopmaker",    label = "L",  name = "JKK Loopmaker",        path = "JKK_ReaTools/JKK_Loopmaker.lua",         icon = "Launcher_Loopmaker" },
    { id = "variator",     label = "V",  name = "JKK Variator",         path = "JKK_ReaTools/JKK_Variator.lua",          icon = "Launcher_Variator" },
    { id = "trackmanager", label = "T",  name = "JKK Track Manager",    path = "JKK_ReaTools/JKK_TrackManager.lua",      icon = "Launcher_TrackManager" },
    { id = "colorpalette", label = "C",  name = "JKK Color Palette",    path = "JKK_ReaTools/JKK_ColorPalette.lua",      icon = "Launcher_ColorPalette" },
    { id = "folderitems",  label = "F",  name = "JKK Folder Items Setup", path = "JKK_ReaTools/JKK_FolderItems_Setup.lua", icon = "Launcher_FolderItems" },
    { id = "xypad",        label = "X",  name = "JKK XY Pad",           path = "JKK_ReaTools/JKK_XYPad.lua",             icon = "Launcher_XYPad" },
    { id = "mediabrowser", label = "M",  name = "JKK Media Browser",    path = "JKK_MediaBrowser/JKK_MediaBrowser.lua",  icon = "Launcher_MediaBrowser" },
    { id = "visualizer",   label = "Vz", name = "JKK Visualizer",       path = "JKK_Visualizer/JKK_Visualizer.lua",      icon = "Launcher_Visualizer" },
    { id = "theme",        label = "Th", name = "JKK Theme",            path = "JKK_ReaTools/JKK_Theme.lua",             icon = "Launcher_Theme" },
}

local SETTINGS_POPUP = "##JKK_ReaTools_LauncherSettings"
local ICON_RECHECK = 2.0
local FILE_RECHECK = 3.0

local function Now() return RPR.time_precise and RPR.time_precise() or os.clock() end

function M.Create(opts)
    opts = opts or {}
    local Theme = opts.theme or {}
    local root_dir = opts.root_dir or (RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/")
    local icon_dir = opts.icon_dir or (root_dir .. "JKK_ReaTools/Modules/Icons/JKK_ReaTools/")
    local L = { ICON_DIR = icon_dir }

    -- 숨김 목록
    local hidden = {}
    for id in (RPR.GetExtState(EXT_SECTION, EXT_HIDDEN) or ""):gmatch("[^,]+") do hidden[id] = true end
    local function SaveHidden()
        local list = {}
        for _, it in ipairs(M.ITEMS) do if hidden[it.id] then list[#list + 1] = it.id end end
        RPR.SetExtState(EXT_SECTION, EXT_HIDDEN, table.concat(list, ","), true)
    end

    -- 설치 여부 (파일 존재) 캐시
    local exists, exists_checked = {}, -math.huge
    local function RefreshExists()
        local now = Now()
        if now - exists_checked < FILE_RECHECK then return end
        exists_checked = now
        for _, it in ipairs(M.ITEMS) do exists[it.id] = RPR.file_exists(root_dir .. it.path) end
    end

    local function Visible()
        RefreshExists()
        local list = {}
        for _, it in ipairs(M.ITEMS) do
            if exists[it.id] and not hidden[it.id] then list[#list + 1] = it end
        end
        return list
    end

    -- 액션 ID 찾기
    --  1) reaper-kb.ini에 이미 등록된 스크립트(SCR 줄)의 경로를 비교해 ID를 얻는다.
    --     → 단축키/툴바/액션 리스트 등 어떤 방법으로 켜도 REAPER의 토글 상태를
    --       매 프레임 읽으므로 버튼 색이 바로 바뀐다 (각 스크립트를 고칠 필요 없음).
    --  2) 등록되어 있지 않으면 처음 누를 때 등록(AddRemoveReaScript)하고 기억한다.
    local cmd_cache = {}
    local KB_RESCAN = 10.0      -- 아직 ID를 모르는 버튼이 있을 때만 다시 읽는 간격(초)
    local kb_checked = -math.huge

    local function NormPath(p)
        return tostring(p or ""):gsub("\\", "/"):gsub("/+", "/"):lower()
    end

    local function ScanKeymap()
        kb_checked = Now()
        local want, any = {}, false
        for _, it in ipairs(M.ITEMS) do
            if (cmd_cache[it.id] or 0) == 0 then
                want[NormPath("JKK_ReaTools/" .. it.path)] = it
                any = true
            end
        end
        if not any then return end
        local f = io.open(RPR.GetResourcePath() .. "/reaper-kb.ini", "r")
        if not f then return end
        for line in f:lines() do
            if line:sub(1, 4) == "SCR " then
                -- SCR <flags> <section> <RSid> "<description>" <path or "path with spaces">
                local section, id, rest = line:match('^SCR%s+%d+%s+(%d+)%s+(%S+)%s+"[^"]*"%s+(.-)%s*$')
                if section == "0" and id then
                    local path = NormPath((rest:gsub('^"(.*)"$', "%1")))
                    for suffix, it in pairs(want) do
                        if path == suffix or path:sub(-(#suffix + 1)) == "/" .. suffix then
                            local c = RPR.NamedCommandLookup("_" .. id)
                            if c and c ~= 0 then
                                cmd_cache[it.id] = c
                                want[suffix] = nil
                            end
                        end
                    end
                end
            end
        end
        f:close()
    end

    local function KnownCommand(it)
        local c = cmd_cache[it.id]
        if c and c ~= 0 then return c end
        if c == nil then
            local named = RPR.GetExtState(EXT_SECTION, EXT_CMD .. it.id)
            c = (named ~= "" and RPR.NamedCommandLookup(named)) or 0
            cmd_cache[it.id] = c
        end
        return c
    end

    -- 시작할 때 한 번 읽고, 모르는 ID가 남아 있으면 가끔 다시 읽는다
    -- (REAPER를 끄지 않고 새로 등록한 스크립트도 따라잡는다).
    ScanKeymap()
    local function MaybeRescan(list)
        if Now() - kb_checked < KB_RESCAN then return end
        for _, it in ipairs(list) do
            if KnownCommand(it) == 0 then ScanKeymap() return end
        end
        kb_checked = Now()
    end
    local function EnsureCommand(it)
        local c = KnownCommand(it)
        if c ~= 0 then return c end
        if not RPR.AddRemoveReaScript then return 0 end
        c = RPR.AddRemoveReaScript(true, 0, root_dir .. it.path, true) or 0
        cmd_cache[it.id] = c
        if c ~= 0 and RPR.ReverseNamedCommandLookup then
            local named = RPR.ReverseNamedCommandLookup(c)
            if named and named ~= "" then
                RPR.SetExtState(EXT_SECTION, EXT_CMD .. it.id, "_" .. named:gsub("^_", ""), true)
            end
        end
        return c
    end
    local function IsRunning(it)
        local c = KnownCommand(it)
        if c == 0 then return false end
        local state = RPR.GetToggleCommandStateEx and RPR.GetToggleCommandStateEx(0, c)
            or RPR.GetToggleCommandState(c)
        return state == 1
    end
    local function Launch(it)
        local c = EnsureCommand(it)
        if c ~= 0 then
            RPR.Main_OnCommand(c, 0)
        else
            RPR.ShowMessageBox("Could not run " .. it.name .. ":\n" .. root_dir .. it.path,
                "JKK_ReaTools", 0)
        end
    end

    -- PNG 아이콘 (없으면 nil → 글자 표시)
    local icon_cache = {}
    local function GetIcon(ctx, it)
        if not RPR.ImGui_CreateImage then return nil end
        local c = icon_cache[it.id]
        if c and c.img then
            if not RPR.ImGui_ValidatePtr or RPR.ImGui_ValidatePtr(c.img, "ImGui_Image*") then return c.img end
            c = nil
        end
        local now = Now()
        if c and c.missing and (now - c.checked) < ICON_RECHECK then return nil end
        local path = icon_dir .. it.icon .. ".png"
        if not RPR.file_exists(path) then
            icon_cache[it.id] = { missing = true, checked = now }
            return nil
        end
        local ok, img = pcall(RPR.ImGui_CreateImage, path)
        if not ok or not img then
            icon_cache[it.id] = { missing = true, checked = now }
            return nil
        end
        pcall(RPR.ImGui_Attach, ctx, img)
        icon_cache[it.id] = { img = img }
        return img
    end

    local function Color(role, fallback)
        if Theme.GetColor then
            local ok, c = pcall(Theme.GetColor, role)
            if ok and type(c) == "number" then return c end
        end
        return fallback
    end

    local function DrawGear(dl, x, y, s, col)
        local cx, cy = x + s / 2, y + s / 2
        local r1, r2 = s * 0.17, s * 0.30
        for k = 0, 7 do
            local a = k * math.pi / 4
            RPR.ImGui_DrawList_AddLine(dl, cx + math.cos(a) * r1, cy + math.sin(a) * r1,
                cx + math.cos(a) * r2, cy + math.sin(a) * r2, col, math.max(1.5, s * 0.11))
        end
        RPR.ImGui_DrawList_AddCircle(dl, cx, cy, s * 0.20, col, 20, math.max(1.2, s * 0.09))
    end

    local function Gap(h) return math.max(2, math.floor(h * 0.15)) end

    -- 오른쪽 정렬을 위한 전체 너비 (런처 버튼들 + 간격 + 설정 버튼)
    function L.Width(ctx, h)
        local n = #Visible()
        local gap = Gap(h)
        return n * h + n * gap + h
    end

    -- 정사각형 버튼 하나: 아이콘이 있으면 이미지, 없으면 글자
    local function LauncherButton(ctx, it, h)
        local running = IsRunning(it)
        if running and Theme.PushButton then Theme.PushButton(ctx, "confirm") end
        local x, y = RPR.ImGui_GetCursorScreenPos(ctx)
        local clicked = RPR.ImGui_Button(ctx, "##JKK_Launcher_" .. it.id, h, h)
        local hovered = RPR.ImGui_IsItemHovered(ctx)
        if running and Theme.PushButton then Theme.PopButton(ctx) end

        local dl = RPR.ImGui_GetWindowDrawList(ctx)
        local text_col = Color("text_main", 0xEDEDEDFF)
        local img = GetIcon(ctx, it)
        local drawn = false
        if img then
            local pad = math.floor(h * 0.18)
            drawn = pcall(RPR.ImGui_DrawList_AddImage, dl, img, x + pad, y + pad, x + h - pad, y + h - pad,
                0, 0, 1, 1, text_col)
        end
        if not drawn then
            local tw, th = RPR.ImGui_CalcTextSize(ctx, it.label)
            RPR.ImGui_DrawList_AddText(dl, x + (h - tw) / 2, y + (h - th) / 2, text_col, it.label)
        end
        if hovered then
            RPR.ImGui_SetTooltip(ctx, it.name .. (running and "  (running: click to close)" or ""))
        end
        if clicked then Launch(it) end
    end

    local function DrawSettingsPopup(ctx)
        -- Always fit the content and never show a scrollbar: moving the window
        -- near a screen edge must not make a scrollbar flicker in and out.
        local popup_flags = RPR.ImGui_WindowFlags_AlwaysAutoResize()
            | RPR.ImGui_WindowFlags_NoScrollbar()
            | RPR.ImGui_WindowFlags_NoScrollWithMouse()
        if not RPR.ImGui_BeginPopup(ctx, SETTINGS_POPUP, popup_flags) then return end
        RPR.ImGui_TextDisabled(ctx, "Launcher Buttons")
        RefreshExists()
        -- Second column starts after the widest first-column checkbox
        -- (measured, so the popup width is the same every frame).
        local frame_h = RPR.ImGui_GetFrameHeight(ctx)
        local inner_x = select(1, RPR.ImGui_GetStyleVar(ctx, RPR.ImGui_StyleVar_ItemInnerSpacing()))
        local col1_w, n_shown = 0, 0
        for _, it in ipairs(M.ITEMS) do
            if exists[it.id] then
                if n_shown % 2 == 0 then
                    local tw = RPR.ImGui_CalcTextSize(ctx, string.format("%s  (%s)", it.name, it.label))
                    col1_w = math.max(col1_w, frame_h + inner_x + tw)
                end
                n_shown = n_shown + 1
            end
        end
        local col2_x = RPR.ImGui_GetCursorPosX(ctx) + col1_w + frame_h
        local col = 0
        for _, it in ipairs(M.ITEMS) do
            if exists[it.id] then
                if col % 2 == 1 then RPR.ImGui_SameLine(ctx, col2_x) end
                local changed, on = RPR.ImGui_Checkbox(ctx,
                    string.format("%s  (%s)##LauncherVis_%s", it.name, it.label, it.id), not hidden[it.id])
                if changed then
                    hidden[it.id] = (not on) or nil
                    SaveHidden()
                end
                col = col + 1
            end
        end
        -- Show All / Hide All: centered in the popup
        -- (icon file names are documented in Modules/Icons/JKK_ReaTools/README.txt)
        RPR.ImGui_Spacing(ctx)
        local bw = math.max((RPR.ImGui_CalcTextSize(ctx, "Show All")), (RPR.ImGui_CalcTextSize(ctx, "Hide All")))
            + 2 * select(1, RPR.ImGui_GetStyleVar(ctx, RPR.ImGui_StyleVar_FramePadding()))
        local spacing = select(1, RPR.ImGui_GetStyleVar(ctx, RPR.ImGui_StyleVar_ItemSpacing()))
        local avail = select(1, RPR.ImGui_GetContentRegionAvail(ctx))
        RPR.ImGui_SetCursorPosX(ctx, RPR.ImGui_GetCursorPosX(ctx) + math.max(0, (avail - (bw * 2 + spacing)) * 0.5))
        if RPR.ImGui_Button(ctx, "Show All##LauncherShowAll", bw, 0) then
            hidden = {}
            SaveHidden()
        end
        RPR.ImGui_SameLine(ctx, 0, spacing)
        if RPR.ImGui_Button(ctx, "Hide All##LauncherHideAll", bw, 0) then
            for _, it in ipairs(M.ITEMS) do hidden[it.id] = true end
            SaveHidden()
        end
        RPR.ImGui_EndPopup(ctx)
    end

    -- 현재 커서 위치부터 버튼들을 그린다 (호출 측이 오른쪽 정렬 위치를 잡는다)
    function L.Draw(ctx, h)
        local gap = Gap(h)
        local list = Visible()
        MaybeRescan(list)
        RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_FramePadding(), 0, 0)
        for i, it in ipairs(list) do
            if i > 1 then RPR.ImGui_SameLine(ctx, 0, gap) end
            LauncherButton(ctx, it, h)
        end
        -- 맨 오른쪽: 버튼 보이기/숨기기 설정
        if #Visible() > 0 then RPR.ImGui_SameLine(ctx, 0, gap) end
        local x, y = RPR.ImGui_GetCursorScreenPos(ctx)
        if RPR.ImGui_Button(ctx, "##JKK_LauncherSettings", h, h) then
            RPR.ImGui_OpenPopup(ctx, SETTINGS_POPUP)
        end
        local hovered = RPR.ImGui_IsItemHovered(ctx)
        DrawGear(RPR.ImGui_GetWindowDrawList(ctx), x + h * 0.15, y + h * 0.15, h * 0.7,
            hovered and Color("text_main", 0xEDEDEDFF) or Color("text_main", 0xEDEDEDFF))
        if hovered then RPR.ImGui_SetTooltip(ctx, "Show / hide launcher buttons") end
        RPR.ImGui_PopStyleVar(ctx, 1)
        DrawSettingsPopup(ctx)
    end

    return L
end

return M
