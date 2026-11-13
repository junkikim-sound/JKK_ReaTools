--========================================================
-- @title JKK_ColorPalette
-- @author Junki Kim
-- @version 1.0.9
-- @provides
--     [nomain] Modules/JKK_ColorPalette_Data.lua
--     [nomain] Modules/JKK_ColorPalette_UI.lua
--========================================================

local reaper = reaper
local ctx = reaper.ImGui_CreateContext("JKK_ColorPalette")

local font = reaper.ImGui_CreateFont('Arial', 14)
reaper.ImGui_Attach(ctx, font)

-- 1. GetResourcePath 기반 절대 경로 설정
local resource_path = reaper.GetResourcePath()
local base_dir = resource_path .. "/Scripts/JKK_ColorPalette/"

-- 2. 현재 스크립트 실행 경로 동적 추출 (fallback용)
local script_dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""

local function load_module(filename)
    -- 1차 시도: GetResourcePath 기준 경로
    local path1 = base_dir .. "Modules/" .. filename
    if reaper.file_exists(path1) then
        return dofile(path1)
    end
    
    -- 2차 시도: relative script_dir 기준 경로
    local path2 = script_dir .. "Modules/" .. filename
    if reaper.file_exists(path2) then
        return dofile(path2)
    end
    
    -- 3차 시도: JKK_ReaTools 모듈 폴더 공유 경로 (필요 시)
    local path3 = resource_path .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/" .. filename
    if reaper.file_exists(path3) then
        return dofile(path3)
    end

    return nil
end

local theme_module = load_module("JKK_Theme_Core.lua")
local ApplyTheme = theme_module and theme_module.ApplyTheme or function(c) return 0, 0 end

local ui_module = load_module("JKK_ColorPalette_UI.lua")

local is_open = true

local function Main()
    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 420, 340, 1500, 1000)
    reaper.ImGui_SetNextWindowSize(ctx, 500, 370, reaper.ImGui_Cond_FirstUseEver())
    
    local style_pop, color_pop = ApplyTheme(ctx)
    reaper.ImGui_PushFont(ctx, font, 14)

    local visible, open_flag = reaper.ImGui_Begin(ctx, 'JKK Color Palette', is_open, reaper.ImGui_WindowFlags_NoCollapse())

    if visible then
        local should_close = false
        if ui_module and ui_module.JKK_ColorPalette_Draw then
            should_close = ui_module.JKK_ColorPalette_Draw(ctx)
        end
        
        if should_close or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then 
            open_flag = false 
        end
        
        reaper.ImGui_End(ctx)
    end
    
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PopStyleVar(ctx, style_pop)
    reaper.ImGui_PopStyleColor(ctx, color_pop)

    is_open = open_flag

    if is_open then
        if not reaper.ImGui_IsAnyItemActive(ctx) then
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then reaper.Main_OnCommand(40044, 0) end
            if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl()) and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z()) then reaper.Main_OnCommand(40029, 0) end
        end
        reaper.defer(Main)
    end
end

reaper.defer(Main)