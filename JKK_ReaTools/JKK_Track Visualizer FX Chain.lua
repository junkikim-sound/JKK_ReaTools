--========================================================
-- @title JKK_Track Visualizer FX Chain
-- @author Junki Kim
-- @version 1.0.03
--========================================================

local r = reaper

-- ===================================================
local FX_TARGETS = {
  { search = "Oscilloscope Meter (Cockos)", name = "JS: Oscilloscope Meter (Cockos)" },
  { search = "Frequency Spectrum Analyzer Meter (Cockos)", name = "JS: Frequency Spectrum Analyzer Meter (Cockos)" },
  { search = "Spectrograph Spectrogram Meter (Cockos)", name = "JS: Spectrograph Spectrogram Meter (Cockos)" }
}
-- ===================================================

-- 특정 트랙에 대상 FX가 있는지 확인
local function TrackHasTargetFX(track)
  local fx_count = r.TrackFX_GetCount(track)
  for i = 0, fx_count - 1 do
    local _, raw_name = r.TrackFX_GetFXName(track, i, "")
    local name_lower = raw_name:lower()
    for _, item in ipairs(FX_TARGETS) do
      if name_lower:find(item.search:lower(), 1, true) then
        return true
      end
    end
  end
  return false
end

-- 대상 FX 삭제
local function RemoveTargetFXFromTrack(track)
  local fx_count = r.TrackFX_GetCount(track)
  for i = fx_count - 1, 0, -1 do
    local _, raw_name = r.TrackFX_GetFXName(track, i, "")
    local name_lower = raw_name:lower()
    for _, item in ipairs(FX_TARGETS) do
      if name_lower:find(item.search:lower(), 1, true) then
        r.TrackFX_Delete(track, i)
        break
      end
    end
  end
end

-- 대상 FX 추가
local function AddTargetFXToTrack(track)
  for _, item in ipairs(FX_TARGETS) do
    r.TrackFX_AddByName(track, item.name, false, -1)
  end
end

-- ===================================================
-- 메인 로직
-- ===================================================

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

local sel_track_count = r.CountSelectedTracks(0)
if sel_track_count == 0 then 
  r.PreventUIRefresh(-1)
  return 
end

-- 1. 선택된 트랙 중 FX가 없는 트랙이 있는지 확인
local has_missing_track = false
for i = 0, sel_track_count - 1 do
  local track = r.GetSelectedTrack(0, i)
  if not TrackHasTargetFX(track) then
    has_missing_track = true
    break
  end
end

-- 2. 조건별 동작 수행
if has_missing_track then
  -- [추가] FX가 없는 트랙에 추가
  for i = 0, sel_track_count - 1 do
    local track = r.GetSelectedTrack(0, i)
    if not TrackHasTargetFX(track) then
      AddTargetFXToTrack(track)
    end
  end
  
  -- Embedded UI 켜기
  r.Main_OnCommand(42340, 0)

else
  -- [삭제] 선택된 모든 트랙에서 FX 삭제
  for i = 0, sel_track_count - 1 do
    local track = r.GetSelectedTrack(0, i)
    RemoveTargetFXFromTrack(track)
  end
  
  -- Embedded UI 끄기
  r.Main_OnCommand(42341, 0)

  -- (참고: FX 삭제 시 트랙 높이를 다시 축소/지정하고 싶다면 40724 등 원하는 액션 실행 가능)

end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock("Toggle Custom FX Set with Action 40723", -1)