--========================================================
-- @title JKK_ReaTools
-- @author Junki Kim
-- @version 1.0.0
--========================================================

local RPR = reaper
local ctx = RPR.ImGui_CreateContext("JKK_ReaTools_Main")
local open = true
local selected_tool = 1
local prev_project_state_count = reaper.GetProjectStateChangeCount(0) 
local current_project_state_count = prev_project_state_count

local theme_path = RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_Theme/JKK_Theme.lua"
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
tools[1] = { name = "Item",     module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/JKK_ReaTools_Modules/JKK_Item Manager_Module.lua") }
tools[2] = { name = "Track",    module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/JKK_ReaTools_Modules/JKK_Track Manager_Module.lua") }
tools[3] = { name = "Timeline", module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/JKK_ReaTools_Modules/JKK_Timeline Manager_Module.lua") }

---------------------------------------------------------
-- UI
---------------------------------------------------------
local function Main()
    current_project_state_count = reaper.GetProjectStateChangeCount(0) 
    
    reaper.ImGui_SetNextWindowSize(ctx, 650, 700, reaper.ImGui_Cond_Once())
    style_pop_count, color_pop_count = ApplyTheme(ctx)

    local visible, open_flag = reaper.ImGui_Begin(ctx, 'JKK_ReaTools', open,
        reaper.ImGui_WindowFlags_NoCollapse())

    -- open = is_open

    if visible then
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
            if current_tool.name == "Item" then
                if current_tool.module.JKK_Item_Manager_Draw then
                    current_tool.module.JKK_Item_Manager_Draw(ctx, prev_project_state_count, current_project_state_count)
                end

            elseif current_tool.name == "Track" then
                if current_tool.module.JKK_Track_Manager_Draw then
                    current_tool.module.JKK_Track_Manager_Draw(ctx)
                end

            elseif current_tool.name == "Timeline" then
                if current_tool.module.JKK_Timeline_Manager_Draw then
                    current_tool.module.JKK_Timeline_Manager_Draw(ctx)
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