--========================================================
-- @title JKK_ReaTools
-- @author Junki Kim
-- @version 0.7.3
-- @provides 
--     [nomain] Modules/JKK_ItemTool_Module.lua
--     [nomain] Modules/JKK_TrackTool_Module.lua
--     [nomain] Modules/JKK_TimelineTool_Module.lua
--     [nomain] Modules/JKK_Theme.lua
--     [nomain] Images/ITEM_Insert FX @streamline.png
--     [nomain] Images/ITEM_Move Items to Edit Cursor @streamline.png
--     [nomain] Images/ITEM_Play @streamline.png
--     [nomain] Images/ITEM_Stop @streamline.png
--     [nomain] Images/ITEM_Random Arrangement @streamline.png
--     [nomain] Images/ITEM_Render Items to Stereo @streamline.png
--     [nomain] Images/ITEM_Render Takes @streamline.png
--     [nomain] Images/REGION_Delete All Regions @remixicon.png
--     [nomain] Images/REGION_Delete in Time Selection @remixicon.png
--     [nomain] Images/TRACK_Create Region @streamline.png
--     [nomain] Images/TRACK_Create Time Selection @streamline.png
--     [nomain] Images/TRACK_Delete Unused Tracks @streamline.png
--     [nomain] Images/TRACK_Follow Group Name @streamline.png
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
    ["ITEM_VOL"]            = { "Volume Batch Controller ", "Adjust the volume of selected items by a specified dB value" },
    ["ITEM_PITCH"]          = { "Pitch Batch Controller ", "Adjust the pitch of selected items in semitones" },
    ["ITEM_PLAYRATE"]       = { "Playrate Batch Controller ", "Change the playback rate of selected items\n(Affects both pitch and length)" },
    ["ITEM_GRP_STRTCH"]     = { "Group Stretcher ", "Stretch the entire group of selected items by a specified ratio" },
    ["ITEM_ARR_STOFST"]     = { "Start Offset ", "Set the starting offset of the randomization area" },
    ["ITEM_ARR_WIDTH"]      = { "Slot Interval ", "Set the width of the area where item slots will be randomized" },
    ["ITEM_ARR_STRTCH"]      = { "Slot Stretch ", "Stretches items within each slot\nwhile keeping slot intervals fixed" },
    ["ITEM_ARR_POS"]        = { "Random Position Range ", "Set the maximum range for random position offsets" },
    ["ITEM_ARR_PITCH"]      = { "Random Pitch Range ", "Sets the maximum range for random pitch shifts" },
    ["ITEM_ARR_PLAYRATE"]   = { "Random Playrate Range ", "Sets the maximum range for random playback rate changes" },
    ["ITEM_ARR_VOL"]        = { "Random Volume Range ", "Sets the maximum range for random volume changes" },
    ["ITEM_ARR_APPLY"]      = { "Random Arrangement ", "Randomize item properties within the defined ranges" },
    ["ITEM_ARR_PLAY"]       = { "Play Next Slot ", "Jump to and play the next item start position" },
    ["ITEM_ARR_STOP"]       = { "Stop ", "Stops playback" },
    ["ITEM_ARR_LIVE"]       = { "Live Update ", "Apply changes in real time while adjusting sliders" },
    ["ITEM_ARR_ARR"]        = { "Shuffle Order ", "Randomly shuffle the order of selected items" },
    ["ITEM_MV_EDIT"]        = { "Move Items to Edit Cursor ", "Moves the selected items to edit cursor" },
    ["ITEM_INSERT_FX"]      = { "Show FX Chain for Item Take ", "Open the FX chain for the selected item take" },
    ["ITEM_RENDER_TAKE"]    = { "Render Items to New Takes ", "Render items to new takes" },
    ["ITEM_RENDER"]         = { "Render Items to Stereo Stem ", "Renders selected items to a stereo file on a new track" },
    ["ITEM_CRT_REGION"]     = { "Region Creator ", "Creates individual regions based on the bounds of each item\n(Name_01, Name_02, …)" },
    ["ITEM_CHNG_COL"]       = { "Change Items Color ", "Changes the color of selected items" },
    
    -- Track Tools
    ["TRACK_ADJ_VOL"]       = { "Volume Batch Controller ", "Adjusts the volume of selected tracks collectively" },
    ["TRACK_ADJ_PAN"]       = { "Panning Batch Controller ", "Adjusts the panning of selected tracks collectively" },
    ["TRACK_LV_SEL"]        = { "Track Selector by Level ", "Select tracks by folder depth\n(0: All, 1: Top-level, 2+: Child tracks)" },
    ["TRACK_RENAME"]        = { "Track Rename ", "Batch rename selected tracks using the entered text\nand add numbering (Name_01, Name_02, …)" },
    ["TRACK_CRT_TS"]        = { "Time Selection Creator ", "Create a time selection based on track item bounds" },
    ["TRACK_CRT_REGION"]    = { "Regions Creator ", "Create regions based on track boundaries (using name of tracks)" },
    ["TRACK_FLWNAME"]       = { "Follow Folder Name ", "Sync track names with their parent folder and add numbering" },
    ["TRACK_DEL_UNSD"]      = { "Remove Unused Tracks ", "Delete empty or unused tracks in the project" },
    ["TRACK_CHNG_COL"]      = { "Change Tracks Color ", "Changes the color of selected tracks" },
    
    -- Timeline Tools
    ["REGION_RENAME"]       = { "Regions Rename ", "Batch rename regions within the time selection\nand adds numbering (Name_01, Name_02, …)" },
    ["REGION_DEL_SELECTED"] = { "Delete Regions in Time Selection ", "Delete regions within the time selection area" },
    ["REGION_DEL_ALL"]      = { "Delete All Regions ", "Deletes all regions in the project" },
    ["REGION_CHNG_COL"]     = { "Change Regions Color ", "Changes the color of regions within the Time Selection" }
}

local shared_info = { hovered_id = nil }
---------------------------------------------------------
-- UI
---------------------------------------------------------
local function Main()
    current_project_state_count = reaper.GetProjectStateChangeCount(0)
    local textcol_title = 0x068FC3FF
    local textcol_gray = 0x808080FF
    
    reaper.ImGui_SetNextWindowSize(ctx, 530, 650, reaper.ImGui_Cond_Once())
    style_pop_count, color_pop_count = ApplyTheme(ctx)

    local visible, open_flag = reaper.ImGui_Begin(ctx, ' ', open,
        reaper.ImGui_WindowFlags_NoCollapse())

    if visible then
        -- Title ========================================================
        RPR.ImGui_PushFont(ctx, font, 24)
        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), textcol_title)
        local text = "JKK_ReaTools"
        RPR.ImGui_Text(ctx, text)
        RPR.ImGui_PopFont(ctx)
        RPR.ImGui_PopStyleColor(ctx, 1)
        RPR.ImGui_SameLine(ctx)
        
        -- Info ========================================================
        local INFO_LINE_SPACING = 12
        local INFO_MAX_LINES    = 2
        local INFO_AREA_HEIGHT  = (INFO_LINE_SPACING * INFO_MAX_LINES) + 5
        local start_y = RPR.ImGui_GetCursorPosY(ctx)
        local desc_text = " "
        if shared_info.hovered_id and widget_descriptions[shared_info.hovered_id] then
            desc_text = widget_descriptions[shared_info.hovered_id]
        end

        if desc_text and type(desc_text) == "table" then
            local title, body = desc_text[1], desc_text[2]
            local window_width = RPR.ImGui_GetWindowWidth(ctx)
            local padding = 10
            local spacing_adjust = -16

            -- Title
            RPR.ImGui_PushFont(ctx, font, 13)
            RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), textcol_title)
            
            local title_width, _ = RPR.ImGui_CalcTextSize(ctx, title)
            RPR.ImGui_SetCursorPosX(ctx, window_width - title_width - padding)
            RPR.ImGui_Text(ctx, title)
            
            RPR.ImGui_PopStyleColor(ctx, 1)
            RPR.ImGui_PopFont(ctx)

            RPR.ImGui_SetCursorPosY(ctx, RPR.ImGui_GetCursorPosY(ctx) + spacing_adjust + 3)

            -- Body
            if body then
                RPR.ImGui_PushFont(ctx, font, 11)
                RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), textcol_gray)
                
                for line in body:gmatch("([^\n]+)") do
                    local line_width, _ = RPR.ImGui_CalcTextSize(ctx, line)
                    RPR.ImGui_SetCursorPosX(ctx, window_width - line_width - padding)
                    RPR.ImGui_Text(ctx, line)
                end
                
                RPR.ImGui_PopStyleColor(ctx, 1)
                RPR.ImGui_PopFont(ctx)
            end
        end

        RPR.ImGui_SetCursorPosY(ctx, start_y + INFO_AREA_HEIGHT + 5)
        reaper.ImGui_Spacing(ctx)

        -- ========================================================
        local changed, current_tab = RPR.ImGui_BeginTabBar(ctx, "ToolTabs")

        -- ========================================================
        if changed then
            for i, tool in ipairs(tools) do
                local is_selected, _ = RPR.ImGui_BeginTabItem(ctx, tool.name)
                if is_selected then
                    if selected_tool ~= i then
                        selected_tool = i
                        shared_info.needs_reload = true
                    end
                    RPR.ImGui_EndTabItem(ctx)
                end
            end
            RPR.ImGui_EndTabBar(ctx)
        end

        local current_tool = tools[selected_tool]
        
        -- ========================================================
        RPR.ImGui_PushFont(ctx, font, 13)
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
        RPR.ImGui_PopFont(ctx)

        -- ========================================================
        local credit_text = "Scripted by Junki Kim"
        RPR.ImGui_PushFont(ctx, font, 12) 
        local credit_width, _ = RPR.ImGui_CalcTextSize(ctx, credit_text)
        local cursor_x2 = RPR.ImGui_GetWindowWidth(ctx) - credit_width - 10
        RPR.ImGui_SetCursorPosX(ctx, math.max(cursor_x2, 150))
        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), textcol_gray)
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