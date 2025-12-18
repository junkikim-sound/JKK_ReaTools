--========================================================
-- @title JKK_ReaTools
-- @author Junki Kim
-- @version 0.6.0
-- @provides 
--     [nomain] Modules/JKK_ItemTool_Module.lua
--     [nomain] Modules/JKK_TrackTool_Module.lua
--     [nomain] Modules/JKK_TimelineTool_Module.lua
--     [nomain] Modules/JKK_Theme.lua
--     [data]   Icons/ITEM_Insert FX @streamline.png
--     [data]   Icons/ITEM_Move Items to Edit Cursor @streamline.png
--     [data]   Icons/ITEM_Play @streamline.png
--     [data]   Icons/ITEM_Random Arrangement @streamline.png
--     [data]   Icons/ITEM_Render Items to Stereo @streamline.png
--     [data]   Icons/ITEM_Render Takes @streamline.png
--     [data]   Icons/REGION_Delete All Regions @remixicon.png
--     [data]   Icons/REGION_Delete in Time Selection @remixicon.png
--     [data]   Icons/TRACK_Create Region @streamline.png
--     [data]   Icons/TRACK_Create Time Selection @streamline.png
--     [data]   Icons/TRACK_Delete Unused Tracks @streamline.png
--     [data]   Icons/TRACK_Follow Group Name @streamline.png
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

--========================================================
local tools = {}
tools[1] = { name = "Item Tools",     module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_ItemTool_Module.lua") }
tools[2] = { name = "Track Tools",    module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_TrackTool_Module.lua") }
tools[3] = { name = "Timeline Tools", module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_TimelineTool_Module.lua") }

local widget_descriptions = {
    -- Item Tools
    ["ITEM_VOL"]            = "Adjusts the volume of selected items by the specified dB.",
    ["ITEM_PITCH"]          = "Adjusts the pitch of selected items in semitones.",
    ["ITEM_PLAYRATE"]       = "Changes the playback rate of selected items.\n(Adjusts both pitch and length)",
    ["ITEM_GRP_STRTCH"]     = "Stretches the entire group of selected items by the ratio.",
    ["ITEM_ARR_STOFST"]     = "Sets the starting offset for the item randomization area.",
    ["ITEM_ARR_WIDTH"]      = "Sets the width of the area where items will be randomized.",
    ["ITEM_ARR_POS"]        = "Sets the maximum range for random position shifts.",
    ["ITEM_ARR_PITCH"]      = "Sets the maximum range for random pitch shifts.",
    ["ITEM_ARR_PLAYRATE"]   = "Sets the maximum range for random playback rate changes.",
    ["ITEM_ARR_VOL"]        = "Sets the maximum range for random volume changes.",
    ["ITEM_ARR_APPLY"]      = "Re-Arrangement:\nRandomizes item properties within the specified ranges.",
    ["ITEM_ARR_PLAY"]       = "Plays and Stop",
    ["ITEM_ARR_LIVE"]       = "Enables real-time updates as sliders are moved.",
    ["ITEM_ARR_ARR"]        = "Enables random rearranging of the selected item order.",
    ["ITEM_MV_EDIT"]        = "Move Items to Edit Cursor:\nMoves the selected items to edit cursor",
    ["ITEM_INSERT_FX"]      = "Show FX chain for item take",
    ["ITEM_RENDER_TAKE"]    = "Render items to new takes",
    ["ITEM_RENDER"]         = "Render Items to Stereo Stem:\nRenders selected items to a stereo file on a new track.",
    ["ITEM_CRT_REGION"]     = "Region Creator:\nCreates individual regions based on the bounds of each item.",
    ["ITEM_CHNG_COL"]       = "Changes the color of selected items.",
    
    -- Track Tools
    ["TRACK_ADJ_VOL"]       = "Adjusts the volume of selected tracks collectively.",
    ["TRACK_ADJ_PAN"]       = "Adjusts the panning of selected tracks collectively.",
    ["TRACK_LV_SEL"]        = "Selects tracks by folder depth.\n(0: All, 1: Top-level, 2+: Child tracks)",
    ["TRACK_RENAME"]        = "Batch renames selected Tracks\nwith the entered text and adds numbering. (Name_01, Name_02, …)",
    ["TRACK_CRT_TS"]        = "Time Selection Creator:\nCreates a Time Selection based on the bounds of the track items.",
    ["TRACK_CRT_REGION"]    = "Regions Creator:\nCreates regions based on track boundaries, (using name of tracks)",
    ["TRACK_FLWNAME"]       = "Follow Folder Name:\nSyncs track names with their parent folder and adds numbering.",
    ["TRACK_DEL_UNSD"]      = "Remove Unused Tracks:\nDeletes empty or unused tracks in the project.",
    ["TRACK_CHNG_COL"]      = "Changes the color of selected tracks.",
    
    -- Timeline Tools
    ["REGION_RENAME"]       = "Batch renames regions within the Time Selection\nand adds numbering. (Name_01, Name_02, …)",
    ["REGION_DEL_SELECTED"] = "Delete Overlapping Regions:\nDeletes regions within the Time Selection area.",
    ["REGION_DEL_ALL"]      = "Delete All Regions:\nDeletes all regions in the project.",
    ["REGION_CHNG_COL"]     = "Changes the color of regions within the Time Selection."
}

-- [추가] 모듈과 정보를 주고받을 공유 변수 (상자)
local shared_info = { hovered_id = nil }
---------------------------------------------------------
-- UI
---------------------------------------------------------
local function Main()
    current_project_state_count = reaper.GetProjectStateChangeCount(0) 
    
    reaper.ImGui_SetNextWindowSize(ctx, 530, 630, reaper.ImGui_Cond_Once())
    style_pop_count, color_pop_count = ApplyTheme(ctx)

    local visible, open_flag = reaper.ImGui_Begin(ctx, 'JKK_ReaTools', open,
        reaper.ImGui_WindowFlags_NoCollapse())

    -- open = is_open

    if visible then
        -- Title ========================================================
        RPR.ImGui_PushFont(ctx, font, 24)
        local text = "JKK_ReaTools"
        RPR.ImGui_Text(ctx, text)
        RPR.ImGui_PopFont(ctx)
        RPR.ImGui_SameLine(ctx)
        
        -- Info ========================================================
        local INFO_LINE_SPACING = 12
        local INFO_MAX_LINES    = 2
        local INFO_AREA_HEIGHT  = (INFO_LINE_SPACING * INFO_MAX_LINES) + 5
        local desc_text = " "
        if shared_info.hovered_id and widget_descriptions[shared_info.hovered_id] then
            desc_text = widget_descriptions[shared_info.hovered_id]
        end

        RPR.ImGui_PushFont(ctx, font, 10) 
        local window_width = RPR.ImGui_GetWindowWidth(ctx)
        local gray = RPR.ImGui_ColorConvertDouble4ToU32(0.6, 0.6, 0.6, 1.0)
        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), gray)

        local line_spacing = 12
        local start_y = RPR.ImGui_GetCursorPosY(ctx)
        local current_line = 0

        for line in desc_text:gmatch("[^\r\n]+") do
            local line_width, _ = RPR.ImGui_CalcTextSize(ctx, line)
            
            -- 가로 위치 정렬
            local cursor_x = window_width - line_width - 10
            RPR.ImGui_SetCursorPosX(ctx, math.max(cursor_x, 150))
            
            -- 세로 위치 정렬
            RPR.ImGui_SetCursorPosY(ctx, start_y + (current_line * line_spacing))
            
            RPR.ImGui_Text(ctx, line)
            current_line = current_line + 1
        end

        RPR.ImGui_PopStyleColor(ctx, 1)
        RPR.ImGui_PopFont(ctx)

        RPR.ImGui_SetCursorPosY(ctx, start_y + INFO_AREA_HEIGHT + 5)

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
                    shared_info.hovered_id = nil 
                    current_tool.module.JKK_ItemTool_Draw(ctx, prev_project_state_count, current_project_state_count, shared_info)
                end

            elseif current_tool.name == "Track Tools" then
                if current_tool.module.JKK_TrackTool_Draw then
                    shared_info.hovered_id = nil 
                    current_tool.module.JKK_TrackTool_Draw(ctx, shared_info)
                end

            elseif current_tool.name == "Timeline Tools" then
                if current_tool.module.JKK_TimelineTool_Draw then
                    shared_info.hovered_id = nil 
                    current_tool.module.JKK_TimelineTool_Draw(ctx, shared_info)
                end
            end 
            
            prev_project_state_count = current_project_state_count
            
        else
            RPR.ImGui_Text(ctx, "Error: Selected module (" .. current_tool.name .. ") failed to load.")
        end
        reaper.ImGui_Spacing(ctx)

        -- ========================================================
        local credit_text = "Scripted by Junki Kim"
        RPR.ImGui_PushFont(ctx, font, 10) 
        local credit_width, _ = RPR.ImGui_CalcTextSize(ctx, credit_text)
        local cursor_x2 = RPR.ImGui_GetWindowWidth(ctx) - credit_width - 10
        RPR.ImGui_SetCursorPosX(ctx, math.max(cursor_x2, 150))

        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), gray)
        RPR.ImGui_Text(ctx, credit_text)
        RPR.ImGui_PopStyleColor(ctx, 1)
        RPR.ImGui_PopFont(ctx)

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