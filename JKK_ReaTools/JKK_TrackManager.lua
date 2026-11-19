--========================================================
-- @title JKK_TrackManager
-- @author Junki Kim
-- @version 1.0.0
-- @provides
--   [main] Actions/JKK_TrackManager_Open.lua
--   [main] Actions/JKK_TrackManager_TrackActivation.lua
--   [nomain] Modules/JKK_TrackManager_Core.lua
--   [nomain] Modules/JKK_TrackManager_UI.lua
--========================================================

local RPR = reaper
if RPR.set_action_options then RPR.set_action_options(1) end
local script_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local installed_dir = RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/"
local function Path(filename)
    local local_path = script_dir .. "Modules/" .. filename
    if RPR.file_exists(local_path) then return local_path end
    return installed_dir .. "Modules/" .. filename
end

local Core = dofile(Path("JKK_TrackManager_Core.lua"))
local Theme = dofile(Path("JKK_Theme_Core.lua"))
local View = dofile(Path("JKK_TrackManager_UI.lua")).Create({core = Core, theme = Theme})

local ctx = RPR.ImGui_CreateContext("JKK_TrackManager_Ctx")
local open = true
local window_flags = RPR.ImGui_WindowFlags_NoCollapse()
    | RPR.ImGui_WindowFlags_NoScrollbar()
    | RPR.ImGui_WindowFlags_NoScrollWithMouse()

local function Main()
    RPR.SetExtState(Core.EXT_SEC, Core.EXT_KEYS.HEARTBEAT, tostring(RPR.time_precise()), false)
    if RPR.GetExtState(Core.EXT_SEC, Core.EXT_KEYS.FOCUS_REQ) == "1" then
        RPR.SetExtState(Core.EXT_SEC, Core.EXT_KEYS.FOCUS_REQ, "0", false)
        if RPR.ImGui_SetNextWindowFocus then RPR.ImGui_SetNextWindowFocus(ctx) end
    end

    RPR.ImGui_SetNextWindowSize(ctx, 920, 540, RPR.ImGui_Cond_FirstUseEver())
    RPR.ImGui_SetNextWindowSizeConstraints(ctx, 540, 260, 16384, 16384)
    local sp, cp = Theme.ApplyTheme(ctx, 1.0)
    local visible, open_flag = RPR.ImGui_Begin(ctx, "JKK Track Manager", open, window_flags)

    if visible then
        View.Draw(ctx, { embedded = false, scale = 1.0 })
    end
    RPR.ImGui_End(ctx)
    RPR.ImGui_PopStyleVar(ctx, sp)
    RPR.ImGui_PopStyleColor(ctx, cp)
    open = open_flag

    if open then
        if not RPR.ImGui_IsAnyItemActive(ctx) then
            if RPR.ImGui_IsKeyPressed(ctx, RPR.ImGui_Key_Space()) then
                RPR.Main_OnCommand(40044, 0)
            end
            if RPR.ImGui_IsKeyDown(ctx, RPR.ImGui_Mod_Ctrl())
                and RPR.ImGui_IsKeyPressed(ctx, RPR.ImGui_Key_Z()) then
                local redo = RPR.ImGui_IsKeyDown(ctx, RPR.ImGui_Mod_Shift())
                RPR.Main_OnCommand(redo and 40030 or 40029, 0)
            end
        end
        RPR.defer(Main)
    else
        RPR.SetExtState(Core.EXT_SEC, Core.EXT_KEYS.HEARTBEAT, "0", false)
        if RPR.ImGui_DestroyContext then RPR.ImGui_DestroyContext(ctx) end
    end
end

RPR.defer(Main)
