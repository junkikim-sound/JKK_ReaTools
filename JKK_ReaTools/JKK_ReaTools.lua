--========================================================
-- @title JKK_ReaTools
-- @author Junki Kim
-- @version 0.9.41
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

--========================================================
local tools = {}
tools[1] = { name = "Item Tools",     module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_ItemTool_Module.lua") }
tools[2] = { name = "Track Tools",    module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_TrackTool_Module.lua") }
tools[3] = { name = "Timeline Tools", module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_TimelineTool_Module.lua") }

---------------------------------------------------------
-- Note & State Tracking Variables
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

    -- [자동 탭 전환을 위한 상태 추적 변수]
    local prev_sel_item = nil
    local prev_sel_track = nil
    local prev_edit_cursor = -1
    local force_tab = nil

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
    
    -- [자동 탭 전환 로직 시작]
    local cur_sel_items_count = reaper.CountSelectedMediaItems(0)
    local cur_sel_tracks_count = reaper.CountSelectedTracks(0)
    local cur_sel_item = cur_sel_items_count > 0 and reaper.GetSelectedMediaItem(0, 0) or nil
    local cur_sel_track = cur_sel_tracks_count > 0 and reaper.GetSelectedTrack(0, 0) or nil
    local cur_edit_cursor = reaper.GetCursorPosition()

    local item_count_changed = (cur_sel_items_count ~= (prev_sel_items_count or 0))
    local track_count_changed = (cur_sel_tracks_count ~= (prev_sel_tracks_count or 0))

    local item_changed = (cur_sel_item ~= prev_sel_item) or item_count_changed
    local track_changed = (cur_sel_track ~= prev_sel_track) or track_count_changed
    local cursor_changed = (cur_edit_cursor ~= prev_edit_cursor)

    local item_gained = item_changed and (cur_sel_items_count > 0)
    local item_lost = item_changed and (cur_sel_items_count == 0)
    local track_gained = track_changed and (cur_sel_tracks_count > 0)

    -- 우선순위에 따른 탭 전환 분기
    if item_gained then
        force_tab = 1 
        
    elseif track_gained and not item_changed then
        force_tab = 2 
        
    elseif item_lost and cur_sel_tracks_count > 0 then
        force_tab = 2
        
    elseif cursor_changed then
        force_tab = 3
        
    else
        force_tab = nil
    end

    -- 상태 업데이트
    prev_sel_item = cur_sel_item
    prev_sel_track = cur_sel_track
    prev_edit_cursor = cur_edit_cursor
    prev_sel_items_count = cur_sel_items_count
    prev_sel_tracks_count = cur_sel_tracks_count
        
    reaper.ImGui_SetNextWindowSize(ctx, 1900, 220, reaper.ImGui_Cond_Once())
    style_pop_count, color_pop_count = ApplyTheme(ctx)

    local visible, open_flag = reaper.ImGui_Begin(ctx, 'JKK_ReaTools', open, reaper.ImGui_WindowFlags_NoCollapse())

    if visible then
        RPR.ImGui_PushFont(ctx, font, 13)
        local JKK_ReaTools_Table    = reaper.ImGui_TableFlags_SizingFixedFit() | 
                                    reaper.ImGui_TableFlags_BordersInnerV()
        if reaper.ImGui_BeginTable(ctx, "JKK_ReaTools_Table", 2, JKK_ReaTools_Table) then
            reaper.ImGui_TableSetupColumn(ctx, 'JKK_ReaTools_Table_01', reaper.ImGui_TableColumnFlags_WidthFixed(), 400)
            reaper.ImGui_TableSetupColumn(ctx, 'JKK_ReaTools_Table_02', reaper.ImGui_TableColumnFlags_WidthFixed(), 3000)
            reaper.ImGui_TableNextColumn(ctx)
            -- NOTE ===================================================
                local NoteTable    = reaper.ImGui_TableFlags_SizingFixedFit()
                if reaper.ImGui_BeginTable(ctx, "note table", 1, NoteTable) then
                    reaper.ImGui_TableSetupColumn(ctx, 'Note Table', reaper.ImGui_TableColumnFlags_WidthFixed(), 390)
                    reaper.ImGui_TableNextColumn(ctx)
                -- Note
                    reaper.ImGui_Text(ctx, " ")
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xE3DB8EFF)
                    reaper.ImGui_SeparatorText(ctx, 'Project Memo')
                    reaper.ImGui_PopStyleColor(ctx)
                    reaper.ImGui_Text(ctx, " ")
                    reaper.ImGui_SameLine(ctx)
                    local changed, new_note = reaper.ImGui_InputTextMultiline(ctx, "##proj_note", project_note, 375, 160) --190
                    
                    if changed then
                        project_note = new_note
                        reaper.SetProjExtState(0, "JKK_ReaTools_Note", "Project_note", project_note)
                    end
                    reaper.ImGui_Spacing(ctx)
                    reaper.ImGui_Text(ctx, " ")
                    reaper.ImGui_SameLine(ctx)
                        if reaper.ImGui_Button(ctx, "Peaks Display Settings", 375, 22) then
                            reaper.Main_OnCommand(42074, 0)
                            reaper.Main_OnCommand(40441, 0)
                        end
                    reaper.ImGui_EndTable(ctx)
                end
            reaper.ImGui_TableNextColumn(ctx)
            -- ========================================================
                reaper.ImGui_Text(ctx, " ")
                reaper.ImGui_SameLine(ctx)
                
                if RPR.ImGui_BeginTabBar(ctx, "ToolTabs") then
                    for i, tool in ipairs(tools) do
                        local flags = 0
                        if force_tab == i then
                            flags = reaper.ImGui_TabItemFlags_SetSelected()
                        end

                        local is_selected, _ = RPR.ImGui_BeginTabItem(ctx, tool.name, nil, flags)
                        if is_selected then
                            if selected_tool ~= i then
                                selected_tool = i
                            end
                            RPR.ImGui_EndTabItem(ctx)
                        end
                    end
                    RPR.ImGui_EndTabBar(ctx)
                end

                local current_tool = tools[selected_tool]
            -- ========================================================
                    reaper.ImGui_Text(ctx, " ")
                    reaper.ImGui_SameLine(ctx)
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
            reaper.ImGui_EndTable(ctx)
        end
        reaper.ImGui_Spacing(ctx)
        RPR.ImGui_PopFont(ctx)
        RPR.ImGui_End(ctx)
    end
    RPR.ImGui_PopStyleVar(ctx, style_pop_count)
    RPR.ImGui_PopStyleColor(ctx, color_pop_count)

    open = open_flag

    -- 루프 및 종료 로직
    if open then
        if not reaper.ImGui_IsAnyItemActive(ctx) then
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then
                reaper.Main_OnCommand(40044, 0)
            end
            if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl()) and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z()) then
                reaper.Main_OnCommand(40029, 0)
            end
            if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl()) and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift()) and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z()) then
                reaper.Main_OnCommand(40030, 0)
            end
        end
        
        RPR.defer(Main)
    else
        if RPR.ImGui_DestroyContext then
            RPR.ImGui_DestroyContext(ctx)
        end
        return 
    end
end

RPR.defer(Main)