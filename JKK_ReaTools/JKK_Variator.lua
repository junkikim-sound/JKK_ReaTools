--========================================================
-- @title JKK_Variator
-- @author Junki Kim
-- @version 1.0.0
-- @noindex
-- Duplicate the selected audio items into randomized variations
-- (Volume / Pan / Pitch / Playrate, static or dynamic points), preview
-- them in the Arrange View and Apply as a single Undo point.
-- Closing the window (X / Esc) cancels and removes every preview clone.
--
-- Modules/
--   JKK_Variator_Random.lua  : deterministic sampling (pure)
--   JKK_Variator_Model.lua   : settings / Link / Lock / generations (pure)
--   JKK_Variator_Layout.lua  : Group / Individual / Gap / collisions (pure)
--   JKK_Variator_Math.lua    : static values, playrate time map, envelopes (pure)
--   JKK_Variator_Item.lua    : snapshot, clone chunk, envelope / stretch marker writer
--   JKK_Variator_Session.lua : preview session, Apply (one Undo), Cancel
--   JKK_Variator_Preview.lua : Space preview transport / restore
--   JKK_Variator_UI.lua      : ReaImGui view
--========================================================

local RPR = reaper
local SCRIPT_TITLE = "JKK Variator"

if not RPR.ImGui_CreateContext then
    RPR.ShowMessageBox("ReaImGui 확장이 필요합니다.\nReaPack > ReaTeam Extensions 에서 ReaImGui를 설치해 주세요.", SCRIPT_TITLE, 0)
    return
end

-- Re-running the action terminates this instance (its atexit cleanup runs),
-- so two Variator sessions can never overlap.
if RPR.set_action_options then RPR.set_action_options(1 | 4) end

local script_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local installed_dir = RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/"
local function Path(filename)
    local local_path = script_dir .. "Modules/" .. filename
    if RPR.file_exists(local_path) then return local_path end
    return installed_dir .. "Modules/" .. filename
end

local Theme        = dofile(Path("JKK_Theme_Core.lua"))
local WindowChrome = dofile(Path("JKK_WindowChrome.lua"))
local Undo         = dofile(Path("JKK_UndoLabels.lua"))
local Session      = dofile(Path("JKK_Variator_Session.lua"))
local Preview      = dofile(Path("JKK_Variator_Preview.lua"))
local View         = dofile(Path("JKK_Variator_UI.lua")).Create({
    theme = Theme, session = Session, preview = Preview, undo = Undo,
})

local ctx = RPR.ImGui_CreateContext("JKK_Variator_Ctx")
-- Space must never "press" the focused widget: keyboard navigation off.
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
    | RPR.ImGui_WindowFlags_AlwaysAutoResize()

local CONTENT_W = 720   -- wide layout: one row per parameter
local open = true
local started = false
local shut = false

local function Shutdown()
    if shut then return end
    shut = true
    View.Shutdown()
    if RPR.set_action_options then RPR.set_action_options(8) end
end
-- Script stop / termination / runtime error: same idempotent cleanup.
RPR.atexit(Shutdown)

local function StartSession()
    local proj = RPR.EnumProjects(-1)
    local leftovers = Session.find_leftovers(proj, nil)
    if #leftovers > 0 then
        local answer = RPR.ShowMessageBox(string.format(
            "이전 JKK Variator 세션에서 정리되지 않은 미리보기 아이템 %d개가 이 프로젝트에 남아 있습니다.\n지금 삭제할까요?",
            #leftovers), SCRIPT_TITLE, 4)
        if answer == 6 then
            Session.delete_leftovers(proj, leftovers, Undo.Label("variator.cleanup_leftovers"))
        end
    end
    local session, info = Session.start(Session.load_settings())
    View.SetSession(session, info)
end

local function Frame()
    if not started then
        started = true
        StartSession()
        if RPR.ImGui_SetNextWindowFocus then RPR.ImGui_SetNextWindowFocus(ctx) end
    end
    local scale = 1.0
    local sp, cp = Theme.ApplyTheme(ctx, scale)
    Theme.PushFont(ctx, scale, "base")
    local pad = 8 * scale
    local w = CONTENT_W * scale + pad * 2
    RPR.ImGui_SetNextWindowSizeConstraints(ctx, w, 0, w, 16384)
    local visible, open_flag = RPR.ImGui_Begin(ctx, SCRIPT_TITLE, open, window_flags)
    if visible then
        if WindowChrome.header(ctx, SCRIPT_TITLE, "variator", View.HeaderInfo()) then open_flag = false end
        if View.Draw(ctx, scale) then open_flag = false end
    end
    RPR.ImGui_End(ctx)
    Theme.PopFont(ctx)
    RPR.ImGui_PopStyleVar(ctx, sp)
    RPR.ImGui_PopStyleColor(ctx, cp)
    open = open_flag
end

local function Main()
    local ok, err = xpcall(Frame, debug.traceback)
    if not ok then
        RPR.ShowConsoleMsg("[JKK_Variator] " .. tostring(err) .. "\n")
        open = false
    end
    if open then
        RPR.defer(Main)
    else
        Shutdown()
    end
end

RPR.defer(Main)
