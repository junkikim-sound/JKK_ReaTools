--========================================================
-- @title JKK_ReaTools
-- @author Junki Kim
-- @version 0.5.8
-- @provides 
--     [nomain] Modules/JKK_ItemTool_Module.lua
--     [nomain] Modules/JKK_TrackTool_Module.lua
--     [nomain] Modules/JKK_TimelineTool_Module.lua
--     [nomain] Modules/JKK_Theme.lua
--========================================================

local RPR = reaper
local ctx = RPR.ImGui_CreateContext("JKK_ReaTools")

local font = reaper.ImGui_CreateFont('Arial', 24)
RPR.ImGui_Attach(ctx, font)

local open = true
local selected_tool = 1
local prev_project_state_count = reaper.GetProjectStateChangeCount(0) 
local current_project_state_count = prev_project_state_count

local theme_path = RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_Theme.lua"
local ApplyTheme = (RPR.file_exists(theme_path) and dofile(theme_path).ApplyTheme) 
                   or function(ctx) return 0, 0 end

local function load_module(path)
    local full_path = RPR.GetResourcePath() .. path
    if not RPR.file_exists(full_path) then
        RPR.MB("Error: Module file not found at " .. full_path, "Module Load Error: File Not Found", 0)
        return nil
    end
    local status, result = pcall(dofile, full_path)
    if not status then
        RPR.MB("Error executing module:\n" .. path .. "\n\nError Message:\n" .. tostring(result), "Module Execution Error", 0)
        return nil
    end
    return result
end

local tools = {}
tools[1] = { name = "Item Tools",     module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_ItemTool_Module.lua") }
tools[2] = { name = "Track Tools",    module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_TrackTool_Module.lua") }
tools[3] = { name = "Timeline Tools", module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_TimelineTool_Module.lua") }
local tool_descriptions = {
    [1] = "Edit, batch rename, and modify items.", -- Item Tools
    [2] = "Manage and configure track properties.", -- Track Tools
    [3] = "Tools for regions and timeline manipulation.", -- Timeline Tools
}
---------------------------------------------------------
-- UI
---------------------------------------------------------
local function Main()
    current_project_state_count = reaper.GetProjectStateChangeCount(0) 
    
    reaper.ImGui_SetNextWindowSize(ctx, 530, 620, reaper.ImGui_Cond_Once())
    style_pop_count, color_pop_count = ApplyTheme(ctx)

    local visible, open_flag = reaper.ImGui_Begin(ctx, 'JKK_ReaTools', open,
        reaper.ImGui_WindowFlags_NoCollapse())

    -- open = is_open

    if visible then
        RPR.ImGui_PushFont(ctx, font, 24)
        local text = "JKK_ReaTools"
        RPR.ImGui_Text(ctx, text)
        RPR.ImGui_PopFont(ctx)
        RPR.ImGui_SameLine(ctx)
        
        -- [오른쪽 정렬을 위한 수정 시작] =================================
        
        -- 1. 타이틀을 그린 후, 커서를 옆으로 이동 (같은 Y 레벨 유지)
        RPR.ImGui_SameLine(ctx)

        -- 2. 설명 텍스트와 폰트 설정
        local desc = tool_descriptions[selected_tool] or ""
        RPR.ImGui_PushFont(ctx, font, 10) 
        
        -- 3. 설명 텍스트의 너비 계산
        local desc_width, _ = RPR.ImGui_CalcTextSize(ctx, desc) 
        
        -- 4. 오른쪽 정렬을 위한 X 좌표 계산
        -- **[오류 해결 부분]**: ImGui_GetStyle 호출을 제거하고 GetWindowWidth와 GetCursorPosX를 직접 사용
        local window_width = RPR.ImGui_GetWindowWidth(ctx) 
        
        -- 일반적으로 윈도우 패딩은 좌우 8.0씩입니다. 이 값을 하드코딩하거나 16.0으로 설정합니다.
        local window_padding_x = 8.0 
        
        -- 텍스트가 시작되어야 할 위치: (전체 너비) - (오른쪽 패딩) - (텍스트 너비)
        local cursor_x_to_set = window_width - window_padding_x - desc_width
        
        -- 5. 현재 커서 위치 (타이틀 바로 옆)를 확인
        local current_cursor_x_after_title = RPR.ImGui_GetCursorPosX(ctx)
        
        -- 6. 계산된 X 좌표로 커서 이동 (단, 타이틀을 침범하지 않도록 함)
        if cursor_x_to_set > current_cursor_x_after_title then
            RPR.ImGui_SetCursorPosX(ctx, cursor_x_to_set)
        else
            -- 공간이 부족하여 타이틀과 겹치는 경우, 그냥 타이틀 옆에 표시
            RPR.ImGui_SetCursorPosX(ctx, current_cursor_x_after_title) 
        end
        
        -- 7. 폰트 색상을 회색으로 변경 (옵션)
        local gray = RPR.ImGui_ColorConvertDouble4ToU32(0.6, 0.6, 0.6, 1.0)
        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), gray)
        
        -- 8. 설명 텍스트 표시
        RPR.ImGui_Text(ctx, desc) 
        
        -- 9. 스타일 및 폰트 해제
        RPR.ImGui_PopStyleColor(ctx, 1)    -- Pop Style Color
        
        -- [오른쪽 정렬을 위한 수정 끝] ===================================
        
        RPR.ImGui_PopFont(ctx) -- Pop title_font
        RPR.ImGui_Separator(ctx)

        -- ========================================================
        local changed, current_tab = RPR.ImGui_BeginTabBar(ctx, "ToolTabs")

        -- ========================================================
        if changed then
            for i, tool in ipairs(tools) do
                local is_selected, _ = RPR.ImGui_BeginTabItem(ctx, tool.name)
                if is_selected then
                    selected_tool = i
                    RPR.ImGui_EndTabItem(ctx)
                end
            end
            RPR.ImGui_EndTabBar(ctx)
        end

        local current_tool = tools[selected_tool]
        
        -- ========================================================
        if current_tool and current_tool.module then
            if current_tool.name == "Item Tools" then
                if current_tool.module.JKK_ItemTool_Draw then
                    current_tool.module.JKK_ItemTool_Draw(ctx, prev_project_state_count, current_project_state_count)
                end

            elseif current_tool.name == "Track Tools" then
                if current_tool.module.JKK_TrackTool_Draw then
                    current_tool.module.JKK_TrackTool_Draw(ctx)
                end

            elseif current_tool.name == "Timeline Tools" then
                if current_tool.module.JKK_TimelineTool_Draw then
                    current_tool.module.JKK_TimelineTool_Draw(ctx)
                end
            end 
            
            prev_project_state_count = current_project_state_count
            
        else
            RPR.ImGui_Text(ctx, "Error: Selected module (" .. current_tool.name .. ") failed to load.")
        end

        -- ========================================================
        RPR.ImGui_PopStyleVar(ctx, style_pop_count)
        RPR.ImGui_PopStyleColor(ctx, color_pop_count)
        RPR.ImGui_End(ctx)
    end

    open = open_flag

    if open then
        RPR.defer(Main)
    else
        if RPR.ImGui_DestroyContext then
            RPR.ImGui_DestroyContext(ctx)
        end
    end
end

RPR.defer(Main)