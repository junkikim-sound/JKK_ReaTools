--========================================================
-- @title JKK_Search
-- @author Junki Kim
-- @version 1.1.0
-- @noindex
-- REAPER 안의 거의 모든 것을 검색하고 즉시 실행하는 검색 창
--  FX(VST/VST3/CLAP/JS/VSTi...), FX Chain, Track Template, Action,
--  Track, Item, Marker/Region, 최근 프로젝트, REAPER FX 폴더(Tags)/Category/Developer
--
-- Modules/
--   JKK_Search_Store.lua   : 설정 / 최근 사용 / 즐겨찾기 저장
--   JKK_Search_Index.lua   : 검색 대상 인덱스 구축
--   JKK_Search_Query.lua   : 매칭 / 점수 / 정렬 / 하이라이트
--   JKK_Search_Actions.lua : 실행 (FX 삽입, 액션 실행 등)
--   JKK_Search_UI.lua      : 화면
--========================================================

local RPR = reaper
local SCRIPT_TITLE = "JKK Search"
local VERSION = "1.0.0"

if not RPR.ImGui_CreateContext then
    RPR.ShowMessageBox("ReaImGui 확장이 필요합니다.\nReaPack > ReaTeam Extensions 에서 ReaImGui를 설치해 주세요.", SCRIPT_TITLE, 0)
    return
end

-- 단축키를 다시 누르면 창이 닫히도록 (토글 동작) + 툴바 버튼 점등
if RPR.set_action_options then RPR.set_action_options(1 | 4) end
RPR.atexit(function()
    if RPR.set_action_options then RPR.set_action_options(8) end
end)

----------------------------------------------------------
-- 모듈 로드
----------------------------------------------------------
local script_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local installed_dir = RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/"

local function Path(filename)
    local candidates = {
        script_dir .. "Modules/" .. filename,
        installed_dir .. "Modules/" .. filename,
        RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/Modules/" .. filename,
    }
    for _, p in ipairs(candidates) do
        if RPR.file_exists(p) then return p end
    end
    return candidates[1]
end

local function Load(filename)
    local path = Path(filename)
    if not RPR.file_exists(path) then
        RPR.ShowMessageBox(filename .. " 를 찾을 수 없습니다.\nModules 폴더 위치를 확인해 주세요.", SCRIPT_TITLE .. " Error", 0)
        return nil
    end
    return dofile(path)
end

local Theme        = Load("JKK_Theme_Core.lua")
local WindowChrome = Load("JKK_WindowChrome.lua")
local Undo         = Load("JKK_UndoLabels.lua")
local Sel          = _G.JKK_SelectionManager or Load("JKK_SelectionManager.lua")
local Store        = Load("JKK_Search_Store.lua")
local Index        = Load("JKK_Search_Index.lua")
local Library      = Load("JKK_Search_Library.lua")
local QueryMod     = Load("JKK_Search_Query.lua")
local ActionsMod   = Load("JKK_Search_Actions.lua")
local UIMod        = Load("JKK_Search_UI.lua")
if not (Theme and WindowChrome and Store and Index and Library and QueryMod and ActionsMod and UIMod) then return end

-- JKK MediaBrowser 연동 (선택 사항: 없거나 실패해도 JKK Search 는 그대로 동작)
local MBLink = nil
do
    local path = Path("JKK_Search_MediaBrowser.lua")
    if RPR.file_exists(path) then
        local ok, mod = pcall(dofile, path)
        -- JKK MediaBrowser 가 설치되어 있지 않으면 (액션 없음) 연동 기능 전체를 숨긴다
        if ok and type(mod) == "table" and mod.Available and mod.Available() then MBLink = mod end
    end
end

local Query   = QueryMod.Create({ index = Index, store = Store, library = Library })
local Actions = ActionsMod.Create({ store = Store, sel = Sel, undo = Undo })
local UI      = UIMod.Create({
    theme = Theme, store = Store, index = Index, query = Query,
    actions = Actions, library = Library, mb = MBLink, sel = Sel, version = VERSION,
})

----------------------------------------------------------
-- ImGui 컨텍스트
----------------------------------------------------------
local ctx = RPR.ImGui_CreateContext("JKK_Search")

-- 방향키가 검색창 밖으로 포커스를 옮기지 않도록 키보드 내비게이션 비활성화
if RPR.ImGui_ConfigVar_Flags and RPR.ImGui_ConfigFlags_NavEnableKeyboard then
    local ok, flags = pcall(RPR.ImGui_GetConfigVar, ctx, RPR.ImGui_ConfigVar_Flags())
    if ok and flags then
        flags = math.floor(flags) & ~RPR.ImGui_ConfigFlags_NavEnableKeyboard()
        pcall(RPR.ImGui_SetConfigVar, ctx, RPR.ImGui_ConfigVar_Flags(), flags)
    end
end

local window_flags = WindowChrome.flags()
    | RPR.ImGui_WindowFlags_NoScrollbar()
    | RPR.ImGui_WindowFlags_NoScrollWithMouse()

-- 첫 프레임 전에 FX 목록 일부를 미리 구축해 즉시 검색 가능하도록
Index.Rebuild()
Index.Step(0.05)

local function ProjectOpts()
    return {
        tracks  = Store.Get("search_tracks"),
        items   = Store.Get("search_items"),
        markers = Store.Get("search_markers"),
    }
end
Index.RefreshProject(true, ProjectOpts())

local open = true
local first_frame = true
local prev_expanded = nil
local MIN_W, MIN_EXPANDED_H = 560, 340   -- 창 최소 크기
local last_w, live_h, live_h_frame = nil, nil, nil
local height_anim = nil   -- 펼침/접힘 애니메이션 { from, to, t0 }

local function RunPending(p)
    if p.mb then
        if not MBLink then return false, "JKK MediaBrowser integration unavailable" end
        return MBLink.Send(p.mb)
    end
    local ok, msg = Actions.ExecuteMany(p.entries, p.opts)
    return ok, msg
end

----------------------------------------------------------
-- 메인 루프
----------------------------------------------------------
local function Main()
    Index.Step(0.012)
    Index.RefreshProject(false, ProjectOpts())

    if first_frame then
        if Store.Get("open_at_mouse") and RPR.GetMousePosition then
            local mx, my = RPR.GetMousePosition()
            if RPR.ImGui_PointConvertNative then
                mx, my = RPR.ImGui_PointConvertNative(ctx, mx, my, false)
            end
            RPR.ImGui_SetNextWindowPos(ctx, mx, my, RPR.ImGui_Cond_Always(), 0.5, 0.3)
        end
        if RPR.ImGui_SetNextWindowFocus then RPR.ImGui_SetNextWindowFocus(ctx) end
    end

    -- 접힘: 높이를 검색줄에 고정(너비만 조절 가능) / 펼침: 마지막으로 쓰던 높이 복원
    local expanded = UI.IsExpanded()
    local saved_h = math.max(MIN_EXPANDED_H, Store.Get("expanded_h"))
    RPR.ImGui_SetNextWindowSize(ctx, 720, saved_h, RPR.ImGui_Cond_FirstUseEver())

    -- 펼침/접힘 애니메이션: 현재 높이 → 목표 높이로 창 높이를 부드럽게 바꾼다
    local now = RPR.time_precise()
    if prev_expanded ~= nil and expanded ~= prev_expanded and live_h_frame then
        if prev_expanded and live_h then Store.Set("expanded_h", math.floor(live_h)) end
        height_anim = {
            from = live_h_frame,
            to = expanded and saved_h or UI.CollapsedHeight(),
            t0 = now,
        }
    end
    local animating = false
    if height_anim then
        local t = (now - height_anim.t0) / UI.AnimDuration
        if t >= 1 then
            height_anim = nil
        else
            local h = height_anim.from + (height_anim.to - height_anim.from) * UI.EaseOutCubic(t)
            RPR.ImGui_SetNextWindowSizeConstraints(ctx, MIN_W, h, 16384, h)
            animating = true
        end
    end
    -- 접히는 동안에는 본문을 계속 그려 내용이 함께 줄어드는 것처럼 보이게
    UI.SetBodyHold(animating and not expanded)

    if animating then
        -- 크기 제약은 위에서 설정
    elseif expanded then
        if prev_expanded == nil then
            -- 펼친 상태로 시작: 저장된 높이를 첫 프레임에 강제 (너비는 그대로)
            RPR.ImGui_SetNextWindowSizeConstraints(ctx, MIN_W, saved_h, 16384, saved_h)
        else
            RPR.ImGui_SetNextWindowSizeConstraints(ctx, MIN_W, MIN_EXPANDED_H, 16384, 16384)
        end
    else
        local ch = UI.CollapsedHeight()
        RPR.ImGui_SetNextWindowSizeConstraints(ctx, MIN_W, ch, 16384, ch)
    end
    prev_expanded = expanded

    local scale = UI.ComputeScale()
    local sp, cp = Theme.ApplyTheme(ctx, scale)
    Theme.PushFont(ctx, scale, "base")
    local visible, open_flag = RPR.ImGui_Begin(ctx, SCRIPT_TITLE, open, window_flags)
    if visible then
        last_w, live_h_frame = RPR.ImGui_GetWindowSize(ctx)
        -- 애니메이션 중간 높이는 "펼친 높이"로 기억하지 않는다
        if expanded and not animating then live_h = live_h_frame end
        if UI.Draw(ctx) then open_flag = false end
    end
    RPR.ImGui_End(ctx)
    Theme.PopFont(ctx)
    RPR.ImGui_PopStyleVar(ctx, sp)
    RPR.ImGui_PopStyleColor(ctx, cp)
    first_frame = false

    local pending = UI.TakePending()
    if pending then
        if pending.close then
            open_flag = false
        else
            UI.SetStatus(RunPending(pending))
        end
    end

    open = open_flag
    if open then
        RPR.defer(Main)
    else
        if UI.IsExpanded() and live_h then Store.Set("expanded_h", math.floor(live_h)) end
        if RPR.ImGui_DestroyContext then RPR.ImGui_DestroyContext(ctx) end
        if pending and pending.close then
            -- 창이 닫히고 REAPER 메인 창으로 포커스가 돌아간 뒤 실행
            RPR.defer(function()
                local ok, msg = RunPending(pending)
                if not ok and msg then
                    RPR.ShowConsoleMsg("[JKK Search] " .. tostring(msg) .. "\n")
                end
            end)
        end
    end
end

RPR.defer(Main)
