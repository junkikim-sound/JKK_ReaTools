--========================================================
-- @title JKK_ReaTools
-- @author Junki Kim
-- @version 0.8.2
-- @provides 
--     [nomain] Modules/JKK_ItemTool_Module.lua
--     [nomain] Modules/JKK_TrackTool_Module.lua
--     [nomain] Modules/JKK_TimelineTool_Module.lua
--     [nomain] Modules/JKK_Theme.lua
--     [nomain] Images/ITEM_Insert FX @streamline.png
--     [nomain] Images/ITEM_Move Items to Edit Cursor @streamline.png
--     [nomain] Images/ITEM_Align Items to Left in Slot @streamline.png
--     [nomain] Images/ITEM_Play @streamline.png
--     [nomain] Images/ITEM_Stop @streamline.png
--     [nomain] Images/ITEM_Random Arrangement @streamline.png
--     [nomain] Images/ITEM_Render Items to Stereo @streamline.png
--     [nomain] Images/ITEM_Render Takes @streamline.png
--     [nomain] Images/REGION_Delete All Regions @remixicon.png
--     [nomain] Images/REGION_Delete in Time Selection @remixicon.png
--     [nomain] Images/TRACK_Create Parallel FX Group @streamline.png
--     [nomain] Images/TRACK_Create Region @streamline.png
--     [nomain] Images/TRACK_Create Time Selection @streamline.png
--     [nomain] Images/TRACK_Delete Unused Tracks @streamline.png
--     [nomain] Images/TRACK_Follow Group Name @streamline.png
--     [nomain] Images/LOGO.png
--========================================================

local RPR = reaper
local ctx = RPR.ImGui_CreateContext("JKK_ReaTools")

local font = reaper.ImGui_CreateFont('Arial', 24)
RPR.ImGui_Attach(ctx, font)

local open = true
local selected_tool = 1
local prev_project_state_count = reaper.GetProjectStateChangeCount(0) 
local current_project_state_count = prev_project_state_count

local image_path = reaper.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Images/LOGO.png"
local image_logo = reaper.ImGui_CreateImage(image_path)
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
    -- Track Tools
    ["TRACK_ADJ_VOL"]       = { "Volume Batch Controller", "Adjusts the volume of selected tracks collectively\n선택된 트랙의 볼륨을 일괄로 조절합니다" },
    ["TRACK_ADJ_PAN"]       = { "Panning Batch Controller", "Adjusts the panning of selected tracks collectively\n선택된 트랙의 패닝을 일괄로 조절합니다" },
    ["TRACK_LV_SEL"]        = { "Track Selector by Level", "Select tracks by folder depth\n폴더 깊이에 따라 트랙을 선택합니다 (0: All, 1: Top-level, 2+: Child tracks)" },
    ["TRACK_RENAME"]        = { "Track Rename", "Batch rename selected tracks using the entered text and add numbering\n입력한 텍스트로 선택된 트랙을 일괄 변경하고 번호를 추가합니다" },
    ["TRACK_CRT_TS"]        = { "Time Selection Creator", "Create a time selection based on track item bounds\n트랙 아이템의 범위를 기준으로 타임 셀렉션을 생성합니다" },
    ["TRACK_CRT_REGION"]    = { "Regions Creator", "Create regions based on track item bounds (using name of tracks)\n트랙 아이템의 범위를 기준으로 리전을 생성합니다 (트랙 이름 사용)" },
    ["TRACK_CRT_PRLGRP"]    = { "Create Parallel FX Group", "Automatically creates a parallel FX setup (Dry + 3 Wet tracks) with Pre-FX sends\n병렬 FX 라우팅(Dry + 3 Wet)을 자동 생성하고 아이템 이동 및 Pre-FX 센드를 연결합니다" },
    ["TRACK_FLWNAME"]       = { "Follow Folder Name", "Sync track names with their parent folder and add numbering\n부모 폴더 트랙 이름을 기준으로 트랙 이름을 동기화하고 번호를 추가합니다" },
    ["TRACK_DEL_UNSD"]      = { "Remove Unused Tracks", "Delete empty or unused tracks in the project\n프로젝트 내 비어 있거나 사용되지 않는 트랙을 삭제합니다" },
    ["TRACK_CHNG_COL"]      = { "Change Tracks Color", "Changes the color of selected tracks\n선택된 트랙의 색상을 변경합니다" },
    
    -- Timeline Tools
    ["REGION_SET_MATRIX"]   = { "Set Master Mix Matrix by Time Selection", "Enable Master Mix in Render Matrix for regions overlapping with time selection\n타임 셀렉션과 겹치는 리전의 Master Mix 렌더 체크를 켜고 나머지는 끕니다" },
    ["REGION_RENAME"]       = { "Regions Rename", "Batch rename regions within the time selection and adds numbering\n타임 셀렉션 내 리전의 이름을 일괄 변경하고 번호를 추가합니다 (Name_01, Name_02, …)" },
    ["REGION_DEL_SELECTED"] = { "Delete Regions in Time Selection", "Delete regions within the time selection area\n타임 셀렉션 영역에 포함된 리전을 삭제합니다" },
    ["REGION_DEL_ALL"]      = { "Delete All Regions", "Deletes all regions in the project\n프로젝트 내 모든 리전을 삭제합니다" },
    ["REGION_CHNG_COL"]     = { "Change Regions Color", "Changes the color of regions within the Time Selection\n타임 셀렉션 내 리전의 색상을 변경합니다" }
}

local shared_info = { hovered_id = nil }
---------------------------------------------------------
-- Note
---------------------------------------------------------
    -- [프로젝트 노트 변수 초기화]
    local project_note = ""
    local last_project_ptr = nil

    -- 현재 프로젝트에서 저장된 노트 불러오기
    local retval, saved_note = reaper.GetProjExtState(0, "JKK_ReaTools_Note", "project_note")
    if retval > 0 then
        project_note = saved_note
    else
        project_note = ""
    end
---------------------------------------------------------
-- UI
---------------------------------------------------------
local function Main()
    current_project_state_count = reaper.GetProjectStateChangeCount(0)
    local textcol_title = 0xE3DB8EFF
    local textcol_gray = 0x808080FF

    local current_project_ptr, _ = reaper.EnumProjects(-1)
    if current_project_ptr ~= last_project_ptr then
        local retval, saved_note = reaper.GetProjExtState(0, "JKK_ReaTools_Note", "project_note")
        if retval > 0 then
            project_note = saved_note
        else
            project_note = ""
        end
        last_project_ptr = current_project_ptr
    end
    
    reaper.ImGui_SetNextWindowSize(ctx, 1900, 220, reaper.ImGui_Cond_Once())
    style_pop_count, color_pop_count = ApplyTheme(ctx)

    local visible, open_flag = reaper.ImGui_Begin(ctx, 'JKK_ReaTools', open,
        reaper.ImGui_WindowFlags_NoCollapse())

    if visible then
        local JKK_ReaTools_Table    = reaper.ImGui_TableFlags_SizingFixedFit() | 
                                    reaper.ImGui_TableFlags_BordersInnerV()
        if reaper.ImGui_BeginTable(ctx, "JKK_ReaTools_Table", 2, table_full) then
            reaper.ImGui_TableSetupColumn(ctx, 'JKK_ReaTools_Table_01', reaper.ImGui_TableColumnFlags_WidthFixed(), 1680)
            reaper.ImGui_TableSetupColumn(ctx, 'JKK_ReaTools_Table_02', reaper.ImGui_TableColumnFlags_WidthFixed(), 1000)
            reaper.ImGui_TableNextColumn(ctx)
            -- ========================================================
                local changed, current_tab = RPR.ImGui_BeginTabBar(ctx, "ToolTabs")
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
            reaper.ImGui_TableNextColumn(ctx)
            -- NOTE ===================================================
                reaper.ImGui_Text(ctx, " ")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SeparatorText(ctx, 'Project Memo')
                reaper.ImGui_Text(ctx, " ")
                reaper.ImGui_SameLine(ctx)
                local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
                local changed, new_note = reaper.ImGui_InputTextMultiline(ctx, "##proj_note", project_note, avail_w, 190)
                
                if changed then
                    project_note = new_note
                    reaper.SetProjExtState(0, "JKK_ReaTools_Note", "Project_note", project_note)
                end
            reaper.ImGui_EndTable(ctx)
        end
        reaper.ImGui_Spacing(ctx)
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