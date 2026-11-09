-- @description Time Selection Context Popup Toolbar (Fixed Pos & Actions)
-- @version 1.3.0

local ctx = reaper.ImGui_CreateContext('TimeSelPopup_Manual')

-- 24색 컬러 팔레트 데이터
local region_colors = {
  {10,70,57}, {14,96,78},  {21,139,114}, {23,156,128},  {69,171,148},  {162,202,189}, {121,18,19}, {156,23,24},  {168,58,59},  {179,93,93},  {202,162,162}, {221,195,195},
  {10,43,70}, {15,64,104}, {23,96,156},  {102,143,182}, {171,186,207}, {225,230,237}, {88,114,47}, {125,162,67}, {159,206,85}, {184,239,99}, {205,244,152}, {226,248,200},
}

local frame_count = 0
local mouse_x, mouse_y = nil, nil

---------------------------------------------------------
-- Helper Functions
---------------------------------------------------------

-- 타임 셀렉션 구간 가져오기
local function GetTimeSelection()
  local ts, te = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if ts == te or te <= ts then return nil, nil end
  return ts, te
end

-- 타임 셀렉션과 중첩된 리전 목록 가져오기
local function GetOverlappingRegions()
  local ts, te = GetTimeSelection()
  if not ts then return nil end

  local _, numMarkers, numRegions = reaper.CountProjectMarkers(0)
  local total = numMarkers + numRegions
  local list = {}

  for i = 0, total - 1 do
    local retval, isRegion, pos, rgnEnd, name, markrgnidx, color = reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and isRegion then
      if pos < te and rgnEnd > ts then
        list[#list+1] = {
          enum_idx = i,
          markrgnidx = markrgnidx,
          pos = pos,
          rgnEnd = rgnEnd,
          name = name,
          color = color
        }
      end
    end
  end
  return list
end

---------------------------------------------------------
-- Action Functions
---------------------------------------------------------

-- 1. Create Region (Action ID 40174)
local function CreateRegionFromTimeSel()
  reaper.Main_OnCommand(40174, 0)
end

-- 2. Set Region Matrix (Master Track)
local function ToggleMasterRenderforOverlappingRegions()
  local ts, te = GetTimeSelection()
  if not ts then return end

  local proj = 0
  local master_track = reaper.GetMasterTrack(proj)
  local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)
  local total_count = num_markers + num_regions
  
  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()
  
  for i = 0, total_count - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnidx = reaper.EnumProjectMarkers3(proj, i)
    if retval > 0 and isrgn then
      if pos < te and rgnend > ts then
        reaper.SetRegionRenderMatrix(proj, markrgnidx, master_track, 1)
      else
        reaper.SetRegionRenderMatrix(proj, markrgnidx, master_track, -1)
      end
    end
  end

  reaper.Undo_EndBlock("Set Region Matrix by Time Selection", -1)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateTimeline()
  reaper.TrackList_AdjustWindows(false)
end

-- 3. Delete Selected Regions
local function DeleteOverlappingRegions()
  local regions = GetOverlappingRegions()
  if not regions or #regions == 0 then return end

  reaper.Undo_BeginBlock()
  -- 역순 삭제로 인덱스 밀림 방지
  for i = #regions, 1, -1 do
    reaper.DeleteProjectMarkerByIndex(0, regions[i].enum_idx)
  end
  reaper.Undo_EndBlock("Delete Overlapping Regions", -1)
  reaper.UpdateArrange()
end

-- 4. Delete All Regions
local function DeleteAllRegions()
  local _, numMarkers, numRegions = reaper.CountProjectMarkers(0)
  if numRegions == 0 then return end

  local confirm = reaper.MB("정말로 모든 리전을 삭제하시겠습니까?", "Delete All Regions", 4)
  if confirm ~= 6 then return end

  reaper.Undo_BeginBlock()
  local total = numMarkers + numRegions
  for i = total - 1, 0, -1 do
    local _, isRegion, _, _, _, markrgnidx = reaper.EnumProjectMarkers3(0, i)
    if isRegion then
      reaper.DeleteProjectMarkerByIndex(0, i)
    end
  end
  reaper.Undo_EndBlock("Delete All Regions", -1)
  reaper.UpdateArrange()
end

-- 5. Set Region Colors
local function SetRegionColors(colorTable)
  if not colorTable then return end
  local regions = GetOverlappingRegions()
  if not regions or #regions == 0 then return end

  local r, g, b = colorTable[1], colorTable[2], colorTable[3]
  local newColor = reaper.ColorToNative(r, g, b) | 0x1000000

  reaper.Undo_BeginBlock()
  for _, rgn in ipairs(regions) do
    reaper.SetProjectMarker3(0, rgn.markrgnidx, true, rgn.pos, rgn.rgnEnd, rgn.name, newColor)
  end
  reaper.Undo_EndBlock("Recolor Regions", -1)
  reaper.UpdateTimeline()
end

---------------------------------------------------------
-- Main Loop
---------------------------------------------------------
local function loop()
  frame_count = frame_count + 1
  local keep_open = true

  -- 첫 프레임에서 ReaImGui 자체 좌표계 기반으로 마우스 위치 획득
  if not mouse_x or not mouse_y then
    mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
  end

  -- 팝업 창 위치 고정
  reaper.ImGui_SetNextWindowPos(ctx, mouse_x + 10, mouse_y + 10, reaper.ImGui_Cond_Always())

  local flags = reaper.ImGui_WindowFlags_NoTitleBar() |
                reaper.ImGui_WindowFlags_NoResize() |
                reaper.ImGui_WindowFlags_AlwaysAutoResize() |
                reaper.ImGui_WindowFlags_NoSavedSettings()

  local visible, open = reaper.ImGui_Begin(ctx, 'TimeSelContextMenu', true, flags)
  if visible then
    
    -- Row 1: Create, Set Matrix, Open Render
    if reaper.ImGui_Button(ctx, 'Create Region') then
      CreateRegionFromTimeSel()
      keep_open = false
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Set Matrix') then
      ToggleMasterRenderforOverlappingRegions()
      keep_open = false
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Open Render') then
      reaper.Main_OnCommand(40015, 0)
      keep_open = false
    end

    -- Row 2: Delete Sel, Delete All
    if reaper.ImGui_Button(ctx, 'Delete Sel Regions') then
      DeleteOverlappingRegions()
      keep_open = false
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Delete All Regions') then
      DeleteAllRegions()
      keep_open = false
    end

    reaper.ImGui_Separator(ctx)

    -- Row 3: 24 Color Palette
    local columns = 12
    for i, col in ipairs(region_colors) do
      local packed = reaper.ImGui_ColorConvertDouble4ToU32(col[1]/255, col[2]/255, col[3]/255, 1)
      reaper.ImGui_PushID(ctx, "rgn_col_" .. i)
      if reaper.ImGui_ColorButton(ctx, "##Color", packed, 0, 18, 18) then
        SetRegionColors(col)
        keep_open = false
      end
      reaper.ImGui_PopID(ctx)

      if i % columns ~= 0 then
        reaper.ImGui_SameLine(ctx)
      end
    end

    -- 외부 클릭 시 창 닫기 처리
    if frame_count > 2 then
      local is_clicked = reaper.ImGui_IsMouseClicked(ctx, 0)
      local is_hovered = reaper.ImGui_IsWindowHovered(ctx, reaper.ImGui_HoveredFlags_AnyWindow())
      if is_clicked and not is_hovered then
        keep_open = false
      end
    end

    reaper.ImGui_End(ctx)
  end

  if keep_open then
    reaper.defer(loop)
  end
end

reaper.defer(loop)