--========================================================
-- @title JKK_Renderer_Queue
-- @author Junki Kim
-- @noindex
--========================================================
-- JKK_Renderer 자체 렌더 큐 (REAPER 내장 Render Queue 대신 사용).
--  * 항목 = 큐에 넣는 순간의 탭 설정 스냅샷 + 대상(아이템/트랙 GUID, Region Matrix) 스냅샷
--  * 렌더 자체는 호스트(JKK_Renderer.lua)의 PerformRender가 한다. 이 모듈은
--    데이터(스냅샷/복원/상태)와 큐 목록 UI만 담당한다.
--
-- 호스트(H) 인터페이스 (Draw에 넘김)
--   H.GetColor(role), H.PushButton(ctx, kind), H.PopButton(ctx)
--   H.ctrl_down          : 이번 프레임 Ctrl(Cmd) 눌림 여부 (체크박스 Ctrl+클릭 = 전체 토글)
--   H.running            : 큐 렌더 진행 중 여부
--   H.on_render(ids)     : ids 목록(순서대로) 렌더 요청
--   H.on_stop()          : 진행 중인 큐 렌더 중지 요청
--   H.on_changed()       : 큐 내용이 바뀜 (저장)

local r = reaper

local Q = {}
Q.__index = Q

Q.PENDING = "pending"
Q.RUNNING = "running"
Q.DONE = "done"
Q.FAILED = "failed"

local FAILED_COLOR = 0xE06C6CFF
local MAX_PREVIEW_NAMES = 60

-- =======================================================
-- GUID helpers
-- =======================================================
local function ItemGUID(item)
  if not item or not r.ValidatePtr(item, "MediaItem*") then return nil end
  local _, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
  return guid ~= "" and guid or nil
end

local function TrackGUID(track)
  if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
  if track == r.GetMasterTrack(0) then return "MASTER" end
  return r.GetTrackGUID(track)
end

local function FindTrack(guid, cache)
  if not guid then return nil end
  if guid == "MASTER" then return r.GetMasterTrack(0) end
  if cache and cache[guid] ~= nil then return cache[guid] or nil end
  local found = false
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if r.GetTrackGUID(tr) == guid then found = tr; break end
  end
  if cache then cache[guid] = found end
  return found or nil
end

local function BuildItemIndex()
  local index = {}
  for i = 0, r.CountMediaItems(0) - 1 do
    local item = r.GetMediaItem(0, i)
    local guid = ItemGUID(item)
    if guid then index[guid] = item end
  end
  return index
end

local function CurrentProjectPath()
  local _, fn = r.EnumProjects(-1)
  return fn or ""
end

local function ProjectDisplayName(path)
  if not path or path == "" then return "(unsaved project)" end
  return path:match("([^\\/]+)$") or path
end

-- =======================================================
-- Data model
-- =======================================================
function Q.New()
  return setmetatable({ entries = {}, next_id = 1 }, Q)
end

-- 저장된 항목 목록을 받아 정리한다 (실행 중이던 항목은 대기로 되돌림)
function Q:SetEntries(list)
  self.entries = {}
  self.next_id = 1
  if type(list) ~= "table" then return end
  for _, e in ipairs(list) do
    if type(e) == "table" and type(e.settings) == "table" then
      e.id = tonumber(e.id) or self.next_id
      if e.status == Q.RUNNING or (e.status ~= Q.DONE and e.status ~= Q.FAILED) then
        e.status = Q.PENDING
      end
      e.checked = e.checked ~= false
      e.targets = type(e.targets) == "table" and e.targets or {}
      self.entries[#self.entries + 1] = e
      if e.id >= self.next_id then self.next_id = e.id + 1 end
    end
  end
end

function Q:Count() return #self.entries end

function Q:Find(id)
  for i, e in ipairs(self.entries) do
    if e.id == id then return e, i end
  end
  return nil
end

function Q:CheckedIds()
  local ids = {}
  for _, e in ipairs(self.entries) do
    if e.checked then ids[#ids + 1] = e.id end
  end
  return ids
end

function Q:Counts()
  local checked, done, failed = 0, 0, 0
  for _, e in ipairs(self.entries) do
    if e.checked then checked = checked + 1 end
    if e.status == Q.DONE then done = done + 1 end
    if e.status == Q.FAILED then failed = failed + 1 end
  end
  return checked, done, failed
end

function Q:SetAllChecked(value)
  for _, e in ipairs(self.entries) do e.checked = value and true or false end
end

function Q:Remove(id)
  local _, idx = self:Find(id)
  if idx then table.remove(self.entries, idx) end
end

function Q:ClearAll()
  self.entries = {}
end

function Q:ClearDone()
  local keep = {}
  for _, e in ipairs(self.entries) do
    if e.status ~= Q.DONE then keep[#keep + 1] = e end
  end
  self.entries = keep
end

-- tab           : 탭 설정 (스칼라 값만 복사)
-- items         : 렌더 대상 목록 ({item=, track=, region=})
-- matrix_ptrs   : { [region_index] = { MediaTrack*, ... } } 또는 nil
-- meta          : { summary=, source_name=, previews={ "file.wav", ... } }
function Q:Add(tab, items, matrix_ptrs, meta)
  local settings = {}
  for k, v in pairs(tab) do
    local t = type(v)
    if t == "number" or t == "string" or t == "boolean" then settings[k] = v end
  end

  local targets = {}
  for _, p in ipairs(items or {}) do
    targets[#targets + 1] = { item = ItemGUID(p.item), track = TrackGUID(p.track), region = p.region }
  end

  local matrix = nil
  if matrix_ptrs then
    matrix = {}
    for region_index, tracks in pairs(matrix_ptrs) do
      local guids = {}
      for _, tr in ipairs(tracks) do
        local g = TrackGUID(tr)
        if g then guids[#guids + 1] = g end
      end
      if #guids > 0 then matrix[region_index] = guids end
    end
  end

  meta = meta or {}
  local names = {}
  for i, name in ipairs(meta.previews or {}) do
    if i > MAX_PREVIEW_NAMES then break end
    names[i] = name
  end

  local entry = {
    id = self.next_id,
    checked = true,
    status = Q.PENDING,
    message = "",
    label = tostring(tab.name or "Render"),
    summary = meta.summary or "",
    source_name = meta.source_name or "",
    project = CurrentProjectPath(),
    added = os.date("%H:%M:%S"),
    finished = "",
    settings = settings,
    targets = targets,
    matrix = matrix,
    file_count = #(meta.previews or {}),
    previews = names,
  }
  self.next_id = self.next_id + 1
  self.entries[#self.entries + 1] = entry
  return entry
end

-- 렌더 직전: 스냅샷의 GUID를 현재 프로젝트 포인터로 되돌린다.
-- 반환: items(목록), matrix_ptrs(또는 nil) / 실패 시 nil, 에러 문자열
function Q.Resolve(entry)
  if (entry.project or "") ~= CurrentProjectPath() then
    return nil, "Queued in another project: " .. ProjectDisplayName(entry.project)
  end

  local src = entry.settings.render_source or 0
  local item_index = nil
  local track_cache = {}
  local items, missing = {}, 0

  for _, t in ipairs(entry.targets or {}) do
    local p = { region = t.region }
    if t.item then
      item_index = item_index or BuildItemIndex()
      p.item = item_index[t.item]
      if not p.item then missing = missing + 1 end
    end
    if t.track then
      p.track = FindTrack(t.track, track_cache)
      if not p.track and src == 1 then missing = missing + 1 end
    end
    -- Master mix 대상은 Auto SR/CH 참고용이므로 없어져도 렌더는 가능하다
    if p.item and not p.track then p.track = r.GetMediaItem_Track(p.item) end
    items[#items + 1] = p
  end

  if src ~= 0 and src ~= 2 and src ~= 3 then
    if missing > 0 then
      return nil, string.format("%d target(s) no longer exist in the project", missing)
    end
    if #items == 0 then return nil, "No render targets" end
  end

  local matrix_ptrs = nil
  if src == 2 or src == 3 then
    matrix_ptrs = {}
    local valid_regions = {}
    local i = 0
    while true do
      local retval, isrgn, _, _, _, idx = r.EnumProjectMarkers(i)
      if retval == 0 then break end
      if isrgn then valid_regions[idx] = true end
      i = i + 1
    end
    local count = 0
    for region_index, guids in pairs(entry.matrix or {}) do
      local ri = tonumber(region_index)
      if ri and valid_regions[ri] then
        local tracks = {}
        for _, g in ipairs(guids) do
          local tr = FindTrack(g, track_cache)
          if tr then tracks[#tracks + 1] = tr end
        end
        if #tracks > 0 then matrix_ptrs[ri] = tracks; count = count + 1 end
      end
    end
    if count == 0 then return nil, "Queued regions no longer exist" end
  end

  return items, matrix_ptrs
end

-- =======================================================
-- UI
-- =======================================================
local function StatusText(e)
  if e.status == Q.DONE then return "Done " .. (e.finished or "") end
  if e.status == Q.FAILED then return "Failed" end
  if e.status == Q.RUNNING then return "Rendering..." end
  return "Pending"
end

local function DrawEntryTooltip(ctx, e)
  if not r.ImGui_BeginTooltip(ctx) then return end
  r.ImGui_Text(ctx, e.label)
  r.ImGui_TextDisabled(ctx, "Source: " .. (e.source_name or ""))
  r.ImGui_TextDisabled(ctx, "Format: " .. (e.summary or ""))
  local dir = e.settings.file_directory or ""
  r.ImGui_TextDisabled(ctx, "Directory: " .. (dir ~= "" and dir or "(project default render path)"))
  r.ImGui_TextDisabled(ctx, "File name: " .. tostring(e.settings.file_pattern or ""))
  r.ImGui_TextDisabled(ctx, "Project: " .. ProjectDisplayName(e.project) .. "   Added: " .. tostring(e.added or ""))
  if e.message and e.message ~= "" then
    r.ImGui_Spacing(ctx)
    if e.status == Q.FAILED then
      r.ImGui_TextColored(ctx, FAILED_COLOR, e.message)
    else
      r.ImGui_Text(ctx, e.message)
    end
  end
  local names = e.previews or {}
  if #names > 0 then
    r.ImGui_Separator(ctx)
    local shown = math.min(#names, 12)
    for i = 1, shown do r.ImGui_Text(ctx, names[i]) end
    local total = math.max(e.file_count or #names, #names)
    if total > shown then r.ImGui_TextDisabled(ctx, string.format("... and %d more", total - shown)) end
  end
  r.ImGui_EndTooltip(ctx)
end

-- 큐 목록 그리기. 반환값 없음 (동작은 H 콜백으로 전달)
function Q:Draw(ctx, H)
  local GetColor = H.GetColor
  local running = H.running
  local checked_n, done_n, failed_n = self:Counts()
  local changed = false

  -- Header: 제목 / 요약 ............ [Clear Done] [Clear All] [Render Queue (n)]
  local start_x = r.ImGui_GetCursorPosX(ctx)
  local full_w = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + 4)
  r.ImGui_SetCursorPosX(ctx, 16)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, GetColor("accent"), "Render Queue")
  r.ImGui_SameLine(ctx)
  local info = string.format("(%d)   %d checked", #self.entries, checked_n)
  if done_n > 0 then info = info .. string.format(" / %d done", done_n) end
  if failed_n > 0 then info = info .. string.format(" / %d failed", failed_n) end
  r.ImGui_TextDisabled(ctx, info)

  local btn_w_small, btn_w_main, gap = 92, 140, 6
  local buttons_w = btn_w_small * 2 + btn_w_main + gap * 2 + 8
  r.ImGui_SameLine(ctx)
  r.ImGui_SetCursorPosX(ctx, math.max(r.ImGui_GetCursorPosX(ctx), start_x + full_w - buttons_w))

  H.PushButton(ctx, "primary")
  local no_clear_done = running or done_n == 0
  if no_clear_done then r.ImGui_BeginDisabled(ctx) end
  if r.ImGui_Button(ctx, "Clear Done##q_clear_done", btn_w_small) then
    self:ClearDone(); changed = true
  end
  if no_clear_done then r.ImGui_EndDisabled(ctx) end
  if r.ImGui_IsItemHovered(ctx, r.ImGui_HoveredFlags_AllowWhenDisabled()) then
    r.ImGui_SetTooltip(ctx, "Remove completed entries from the queue.")
  end
  r.ImGui_SameLine(ctx, 0, gap)
  if running then r.ImGui_BeginDisabled(ctx) end
  if r.ImGui_Button(ctx, "Clear All##q_clear_all", btn_w_small) then
    self:ClearAll(); changed = true
  end
  if running then r.ImGui_EndDisabled(ctx) end
  if r.ImGui_IsItemHovered(ctx, r.ImGui_HoveredFlags_AllowWhenDisabled()) then
    r.ImGui_SetTooltip(ctx, "Remove every entry from the queue.")
  end
  H.PopButton(ctx)

  r.ImGui_SameLine(ctx, 0, gap)
  if running then
    H.PushButton(ctx, "highlight")
    if r.ImGui_Button(ctx, "Stop##q_stop", btn_w_main) then H.on_stop() end
    H.PopButton(ctx)
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Stop after the entry that is currently rendering.")
    end
  else
    H.PushButton(ctx, "confirm")
    if checked_n == 0 then r.ImGui_BeginDisabled(ctx) end
    if r.ImGui_Button(ctx, string.format("Render Queue (%d)##q_render", checked_n), btn_w_main) then
      H.on_render(self:CheckedIds())
    end
    if checked_n == 0 then r.ImGui_EndDisabled(ctx) end
    H.PopButton(ctx)
    if r.ImGui_IsItemHovered(ctx, r.ImGui_HoveredFlags_AllowWhenDisabled()) then
      r.ImGui_SetTooltip(ctx, "Render checked entries one after another.\nCtrl+click a checkbox to check or uncheck all entries.")
    end
  end

  r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + 2)
  r.ImGui_Indent(ctx, 16)

  local done_bg = (GetColor("btn_confirm") & 0xFFFFFF00) | 0x50
  local failed_bg = (FAILED_COLOR & 0xFFFFFF00) | 0x40
  local running_bg = (GetColor("slider") & 0xFFFFFF00) | 0x50
  local remove_id = nil
  local render_one = nil

  local table_flags = r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_ScrollY() | r.ImGui_TableFlags_BordersInnerH()
  if r.ImGui_BeginTable(ctx, "QueueTable", 5, table_flags) then
    r.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
    r.ImGui_TableSetupColumn(ctx, "##chk", r.ImGui_TableColumnFlags_WidthFixed(), 22)
    r.ImGui_TableSetupColumn(ctx, "Entry", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableSetupColumn(ctx, "Files", r.ImGui_TableColumnFlags_WidthFixed(), 40)
    r.ImGui_TableSetupColumn(ctx, "Status", r.ImGui_TableColumnFlags_WidthFixed(), 104)
    r.ImGui_TableSetupColumn(ctx, "##del", r.ImGui_TableColumnFlags_WidthFixed(), 22)
    r.ImGui_TableHeadersRow(ctx)

    for _, e in ipairs(self.entries) do
      r.ImGui_PushID(ctx, e.id)
      r.ImGui_TableNextRow(ctx)
      if e.status == Q.DONE then
        r.ImGui_TableSetBgColor(ctx, r.ImGui_TableBgTarget_RowBg1(), done_bg)
      elseif e.status == Q.FAILED then
        r.ImGui_TableSetBgColor(ctx, r.ImGui_TableBgTarget_RowBg1(), failed_bg)
      elseif e.status == Q.RUNNING then
        r.ImGui_TableSetBgColor(ctx, r.ImGui_TableBgTarget_RowBg1(), running_bg)
      end

      -- 1) 체크박스 (Ctrl+클릭 = 전체)
      r.ImGui_TableNextColumn(ctx)
      if running then r.ImGui_BeginDisabled(ctx) end
      local chk_changed, chk_val = r.ImGui_Checkbox(ctx, "##q_chk", e.checked)
      if chk_changed then
        if H.ctrl_down then self:SetAllChecked(chk_val) else e.checked = chk_val end
        changed = true
      end
      if running then r.ImGui_EndDisabled(ctx) end

      -- 2) 이름 + 요약 (완료 항목은 흐리게)
      r.ImGui_TableNextColumn(ctx)
      r.ImGui_AlignTextToFramePadding(ctx)
      local is_done = e.status == Q.DONE
      local row_label = e.label .. "   " .. tostring(e.settings.file_pattern or "")
      local label_w = r.ImGui_CalcTextSize(ctx, row_label)
      if is_done then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), GetColor("status")) end
      r.ImGui_Selectable(ctx, row_label .. "##q_row", false, 0, label_w, 0)
      if is_done then r.ImGui_PopStyleColor(ctx, 1) end
      if r.ImGui_IsItemHovered(ctx) then DrawEntryTooltip(ctx, e) end
      if r.ImGui_BeginPopupContextItem(ctx, "q_row_ctx") then
        if r.ImGui_MenuItem(ctx, "Render This Entry", nil, false, not running) then render_one = e.id end
        if r.ImGui_MenuItem(ctx, "Mark as Pending", nil, false, not running and e.status ~= Q.PENDING) then
          e.status = Q.PENDING; e.message = ""; e.finished = ""; changed = true
        end
        r.ImGui_Separator(ctx)
        if r.ImGui_MenuItem(ctx, "Remove from Queue", nil, false, not running) then remove_id = e.id end
        r.ImGui_EndPopup(ctx)
      end
      r.ImGui_SameLine(ctx)
      r.ImGui_TextDisabled(ctx, (e.summary or ""))

      -- 3) 파일 수
      r.ImGui_TableNextColumn(ctx)
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_Text(ctx, tostring(e.file_count or 0))

      -- 4) 상태
      r.ImGui_TableNextColumn(ctx)
      r.ImGui_AlignTextToFramePadding(ctx)
      if e.status == Q.DONE then
        r.ImGui_TextColored(ctx, GetColor("text_main"), StatusText(e))
      elseif e.status == Q.FAILED then
        r.ImGui_TextColored(ctx, FAILED_COLOR, StatusText(e))
        if r.ImGui_IsItemHovered(ctx) and e.message ~= "" then r.ImGui_SetTooltip(ctx, e.message) end
      elseif e.status == Q.RUNNING then
        r.ImGui_TextColored(ctx, GetColor("accent"), StatusText(e))
      else
        r.ImGui_TextDisabled(ctx, StatusText(e))
      end

      -- 5) 삭제
      r.ImGui_TableNextColumn(ctx)
      if running then r.ImGui_BeginDisabled(ctx) end
      if r.ImGui_Button(ctx, "X##q_del", 20, 0) then remove_id = e.id end
      if running then r.ImGui_EndDisabled(ctx) end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Remove from queue") end

      r.ImGui_PopID(ctx)
    end
    r.ImGui_EndTable(ctx)
  end
  r.ImGui_Unindent(ctx, 16)

  if remove_id then self:Remove(remove_id); changed = true end
  if render_one then H.on_render({ render_one }) end
  if changed then H.on_changed() end
end

return Q
