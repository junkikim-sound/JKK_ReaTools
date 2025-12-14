--========================================================
-- @title JKK_ItemTool_Module
-- @author Junki Kim
-- @version 0.5.5
-- @noindex
--========================================================

-- local ctx = reaper.ImGui_CreateContext('JKK_ItemTool')
local open = true

local theme_path = reaper.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_Theme/JKK_Theme.lua"
local theme_module = nil
if reaper.file_exists(theme_path) then
    theme_module = dofile(theme_path)
end

local ApplyTheme = theme_module and theme_module.ApplyTheme or function(ctx) return 0, 0 end
local style_pop_count, color_pop_count

-- Default Value
local adjust_vol = 0.0
local adjust_pitch = 0
local adjust_rate = 1.0

local group_stretch_ratio = 1.0
local prev_group_stretch_ratio = 1.0

local start_offset = 1
local width        = 5
local pos_range    = 0
local pitch_range      = 0
local playback_range   = 0
local vol_range        = 0

-- Checkbox Default Value
local random_pos     = true
local random_pitch   = true
local random_play    = true
local random_vol     = true
local random_order   = false
local live_update    = true

-- State tracking for selection change and initialization
local prev_project_state_count = reaper.GetProjectStateChangeCount(0) 

-- Save
local prev_start_offset, prev_width, prev_pos_range = start_offset, width, pos_range
local prev_pitch_range, prev_playback_range, prev_vol_range = pitch_range, playback_range, vol_range
local prev_random_pos, prev_random_pitch, prev_random_play, prev_random_vol, prev_random_order =
    random_pos, random_pitch, random_play, random_vol, random_order

-- freeze
local stored_offsets    = {}
local stored_pitch      = {}
local stored_playrates  = {}
local stored_vols       = {}

-- Slot Persistent
local persistentSlots = {}

-- Regions Renamer
local reaper = reaper
local base_name = ""

-- Color Palette Data (24 Colors)
local item_colors = {
  {255, 100, 100}, {255, 150, 100}, {255, 200, 100}, {255, 255, 100}, {200, 255, 100}, {100, 255, 100},
  {100, 255, 150}, {100, 255, 200}, {100, 255, 255}, {100, 200, 255}, {100, 150, 255}, {100, 100, 255},
  {150, 100, 255}, {200, 100, 255}, {255, 100, 255}, {255, 100, 200}, {255, 100, 150}, {200, 200, 200},
  {128, 0, 0},     {128, 128, 0},   {0, 128, 0},     {0, 128, 128},   {0, 0, 128},     {128, 0, 128}
}

math.randomseed(os.time())

----------------------------------------------------------
-- Function: Batch Item Controller
----------------------------------------------------------
function ApplyBatchVolume()
    local cnt = reaper.CountSelectedMediaItems(0)
    if cnt == 0 then return end
    reaper.Undo_BeginBlock()

    local linear_vol = 10^(adjust_vol / 20)
    for i = 0, cnt - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        reaper.SetMediaItemInfo_Value(item, "D_VOL", linear_vol)
    end
    
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Batch Volume Applied", -1)
end

function ApplyBatchPitch()
    local cnt = reaper.CountSelectedMediaItems(0)
    if cnt == 0 then return end
    reaper.Undo_BeginBlock()

    for i = 0, cnt - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        reaper.SetMediaItemTakeInfo_Value(reaper.GetActiveTake(item), "D_PITCH", adjust_pitch)
    end
    
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Batch Pitch Applied", -1)
end

function ApplyBatchRate()
    local cnt = reaper.CountSelectedMediaItems(0)
    if cnt == 0 then return end
    reaper.Undo_BeginBlock()

    for i = 0, cnt - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        if take then
            reaper.SetMediaItemInfo_Value(item, "B_PPITCH", 0) -- Turn off preserve pitch
            
            local current_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local current_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
            
            local source = reaper.GetMediaItemTake_Source(take)
            if source then
                local origin_length = current_length * current_rate
                local adjust_length = origin_length / adjust_rate
                reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", adjust_rate)
                reaper.SetMediaItemLength(item, adjust_length, true)
            end
        end
    end
    
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Batch Playback Rate Applied", -1)
end

----------------------------------------------------------
-- Function: Group Time Stretch
----------------------------------------------------------
function ApplyGroupStretch(stretch_ratio)
    local cnt = reaper.CountSelectedMediaItems(0)
    if cnt < 2 then 
      return 
    end

    reaper.Undo_BeginBlock()

    local selected_items = {}
    local min_pos = 999999999
    
    for i = 0, cnt - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        
        local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
        
        if item_pos < min_pos then min_pos = item_pos end
        
        table.insert(selected_items, {
            item = item,
            take = take,
            pos = item_pos,
            len = item_len,
            rate = item_rate
        })
    end

    local stretch_factor = stretch_ratio / prev_group_stretch_ratio

    for _, data in ipairs(selected_items) do
        local item = data.item
        local take = data.take
        
        local pos_offset = data.pos - min_pos
        local new_pos = min_pos + (pos_offset * stretch_factor)
        local new_len = data.len * stretch_factor
        local new_rate = data.rate / stretch_factor
        
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)
        reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", new_rate)
    end
    
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Group Time Stretch Applied", -1)
end

----------------------------------------------------------
-- Live Update Check & Settings Load/Save
----------------------------------------------------------
function has_changed()
    return (
        start_offset ~= prev_start_offset or
        width        ~= prev_width or
        pos_range    ~= prev_pos_range or
        pitch_range  ~= prev_pitch_range or
        playback_range ~= prev_playback_range or
        vol_range    ~= prev_vol_range or
        random_pos   ~= prev_random_pos or
        random_pitch ~= prev_random_pitch or
        random_play  ~= prev_random_play or
        random_vol   ~= prev_random_vol or
        random_order ~= prev_random_order
    )
end

-- Range 슬라이더 값만 변경되었는지 확인하는 함수
function has_range_value_changed()
    return (
        pos_range    ~= prev_pos_range or
        pitch_range  ~= prev_pitch_range or
        playback_range ~= prev_playback_range or
        vol_range    ~= prev_vol_range
    )
end

function update_prev()
    prev_start_offset = start_offset
    prev_width        = width
    prev_pos_range    = pos_range
    prev_pitch_range  = pitch_range
    prev_playback_range = playback_range
    prev_vol_range    = vol_range
    prev_random_pos   = random_pos
    prev_random_pitch = random_pitch
    prev_random_play  = random_play
    prev_random_vol   = random_vol
    prev_random_order = random_order
end

local function LoadSettings()
    start_offset = tonumber(reaper.GetExtState("JKK_ItemTool", "start_offset")) or 1.0
    width = tonumber(reaper.GetExtState("JKK_ItemTool", "width")) or 5.0
    pos_range = tonumber(reaper.GetExtState("JKK_ItemTool", "pos_range")) or 0.0
    pitch_range = tonumber(reaper.GetExtState("JKK_ItemTool", "pitch_range")) or 0.0
    playback_range = tonumber(reaper.GetExtState("JKK_ItemTool", "playback_range")) or 0.0
    vol_range = tonumber(reaper.GetExtState("JKK_ItemTool", "vol_range")) or 0.0
    local function LoadFlag(namespace, key, default)
        local v = reaper.GetExtState(namespace, key)
        if v == "1" then return true end
        if v == "0" then return false end
        return default
    end

    random_pos   = LoadFlag("JKK_ItemTool", "random_pos", true)
    random_pitch = LoadFlag("JKK_ItemTool", "random_pitch", true)
    random_play  = LoadFlag("JKK_ItemTool", "random_play", true)
    random_vol   = LoadFlag("JKK_ItemTool", "random_vol", true)
    random_order = LoadFlag("JKK_ItemTool", "random_order", false)
    live_update  = LoadFlag("JKK_ItemTool", "live_update", true)

    update_prev() 
end

local function SaveSettings()
    reaper.SetExtState("JKK_ItemTool", "start_offset", tostring(start_offset), true)
    reaper.SetExtState("JKK_ItemTool", "width", tostring(width), true)
    reaper.SetExtState("JKK_ItemTool", "pos_range", tostring(pos_range), true)
    reaper.SetExtState("JKK_ItemTool", "pitch_range", tostring(pitch_range), true)
    reaper.SetExtState("JKK_ItemTool", "playback_range", tostring(playback_range), true)
    reaper.SetExtState("JKK_ItemTool", "vol_range", tostring(vol_range), true)
    
    reaper.SetExtState("JKK_ItemTool", "random_pos", random_pos and "1" or "0", true)
    reaper.SetExtState("JKK_ItemTool", "random_pitch", random_pitch and "1" or "0", true)
    reaper.SetExtState("JKK_ItemTool", "random_play", random_play and "1" or "0", true)
    reaper.SetExtState("JKK_ItemTool", "random_vol", random_vol and "1" or "0", true)
    reaper.SetExtState("JKK_ItemTool", "random_order", random_order and "1" or "0", true)
    reaper.SetExtState("JKK_ItemTool", "live_update", live_update and "1" or "0", true)
end

LoadSettings()

----------------------------------------------------------
-- Helper Functions for Arranger
----------------------------------------------------------
local function generate_random_slots(items, max_count)
    local slots = {}
    for i = 1, max_count do slots[i] = nil end
    for _, item in ipairs(items) do
        local idx
        repeat idx = math.random(1, max_count) until slots[idx] == nil
        slots[idx] = item
    end
    return slots
end

local function create_default_slots(items, max_count)
    local slots = {}
    for i = 1, max_count do slots[i] = items[i] or nil end
    return slots
end

----------------------------------------------------------
-- Spacing Only Logic (Start Offset & Width)
----------------------------------------------------------
function apply_spacing_only()
    local cnt = reaper.CountSelectedMediaItems(0)
    if cnt == 0 then return end

    local _, grid_size = reaper.GetSetProjectGrid(0, false)
    local start_pos = reaper.GetCursorPosition() + grid_size * start_offset * 2
    local spacing   = grid_size * width * 2

    local track_items = {}
    for i = 0, cnt - 1 do
        local item  = reaper.GetSelectedMediaItem(0, i)
        local track = reaper.GetMediaItem_Track(item)
        track_items[track] = track_items[track] or {}
        table.insert(track_items[track], item)
    end

    local max_count = 0
    for _, items in pairs(track_items) do
        if #items > max_count then max_count = #items end
    end
    if max_count < 1 then max_count = 1 end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    for track, items in pairs(track_items) do
        local slots = persistentSlots[track] or create_default_slots(items, max_count)
        
        for slot_index = 1, max_count do
            local item = slots[slot_index]
            if item then
                local base_pos  = start_pos + spacing * (slot_index - 1)
                local final_pos = base_pos

                if stored_offsets[item] ~= nil then
                    final_pos = base_pos + stored_offsets[item]
                end

                reaper.SetMediaItemInfo_Value(item, "D_POSITION", final_pos)
            end
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Spacing Updated", -1)
    reaper.UpdateArrange()
end


----------------------------------------------------------
-- Arrange Items Logic (Full Randomization/Arrangement)
----------------------------------------------------------
function arrange_items()
    local cnt = reaper.CountSelectedMediaItems(0)
    if cnt == 0 then return end

    local current_random_pos   = random_pos
    local current_random_pitch = random_pitch
    local current_random_play  = random_play
    local current_random_vol   = random_vol
    local current_random_order = random_order

    local _, grid_size = reaper.GetSetProjectGrid(0, false)
    local start_pos = reaper.GetCursorPosition() + grid_size * start_offset * 2
    local spacing   = grid_size * width * 2

    local track_items = {}
    for i = 0, cnt - 1 do
        local item  = reaper.GetSelectedMediaItem(0, i)
        local track = reaper.GetMediaItem_Track(item)
        track_items[track] = track_items[track] or {}
        table.insert(track_items[track], item)
    end

    for track, items in pairs(track_items) do
        table.sort(items, function(a, b)
            return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
        end)
    end

    local max_count = 0
    for _, items in pairs(track_items) do
        if #items > max_count then max_count = #items end
    end
    if max_count < 1 then max_count = 1 end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    for track, items in pairs(track_items) do
        local slots = nil
        if current_random_order then
            slots = generate_random_slots(items, max_count)
            persistentSlots[track] = slots
        else
            if persistentSlots[track] then
                slots = persistentSlots[track]
            else
                slots = create_default_slots(items, max_count)
                persistentSlots[track] = slots
            end
        end
        
        -- Freeze logic preservation
        if prev_random_pitch and not random_pitch then
            for slot_index = 1, max_count do
                local item = slots[slot_index]
                if item then
                    local take = reaper.GetActiveTake(item)
                    if take then stored_pitch[take] = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH") end
                end
            end
        end
        
        if prev_random_play and not random_play then
            for slot_index = 1, max_count do
                local item = slots[slot_index]
                if item then
                    local take = reaper.GetActiveTake(item)
                    if take then stored_playrates[take] = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") end
                end
            end
        end
        if prev_random_vol and not random_vol then
            for slot_index = 1, max_count do
                local item = slots[slot_index]
                if item then stored_vols[item] = reaper.GetMediaItemInfo_Value(item, "D_VOL") end
            end
        end
    end

    for track, items in pairs(track_items) do
        local slots = persistentSlots[track]

        for slot_index = 1, max_count do
            local item = slots[slot_index]
            if item then
                local take = reaper.GetActiveTake(item)

                if take then
                    -- Pitch Randomization
                    if current_random_pitch then
                        local rnd = (math.random() * pitch_range * 2) - pitch_range
                        reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", rnd)
                        stored_pitch[take] = rnd
                    else
                        if stored_pitch[take] ~= nil then
                            reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", stored_pitch[take])
                        end
                    end
                end

                if take then
                    -- Playrate Randomization
                    if current_random_play then
                        local rnd = (math.random() * playback_range * 2) - playback_range
                        local rate = 2 ^ (rnd / 12)
                        
                        local current_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                        local current_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                        local origin_length = current_length * current_rate
                        local adjust_length = origin_length / rate
                        reaper.SetMediaItemLength(item, adjust_length, true)

                        reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
                        stored_playrates[take] = rate
                    else
                        if stored_playrates[take] ~= nil then
                            reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", stored_playrates[take])
                        end
                    end
                end

                local base_pos  = start_pos + spacing * (slot_index - 1)
                local final_pos = base_pos

                -- Position Randomization
                if current_random_pos then
                    local offset = (math.random() * pos_range * 2) - pos_range
                    final_pos = base_pos + offset
                    stored_offsets[item] = offset
                else
                    if stored_offsets[item] ~= nil then
                        final_pos = base_pos + stored_offsets[item]
                    else
                        final_pos = base_pos
                    end
                end

                reaper.SetMediaItemInfo_Value(item, "D_POSITION", final_pos)

                -- Volume Randomization
                if current_random_vol then
                    local v = 1.0
                    if vol_range > 0 then
                        v = 1.0 + ((math.random() * 2 - 0.5) * (vol_range / 8) ) 
                        if v < 0 then v = 0 end
                    end
                    stored_vols[item] = v -- Use item as key for vol storage
                    reaper.SetMediaItemInfo_Value(item, "D_VOL", v)
                else
                    if stored_vols[item] ~= nil then
                        reaper.SetMediaItemInfo_Value(item, "D_VOL", stored_vols[item])
                    end
                end
            end
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Variator Updated", -1)
    reaper.UpdateArrange()
end

----------------------------------------------------------
-- Function: RegionCreate
----------------------------------------------------------
local function CreateRegionsFromSelectedItems()
    local project = reaper.EnumProjects(-1, 0)
    if not project then return end

    local sel_items = {}
    local item_count = reaper.CountSelectedMediaItems(project)

    if item_count == 0 then
        return
    end

    -- Collect item start/end
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(project, i)
        local start_time = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local end_time = start_time + length
        table.insert(sel_items, {start=start_time, end_=end_time})
    end

    -- Sort by start time
    table.sort(sel_items, function(a, b) return a.start < b.start end)

    local regions_to_create = {}
    local current_start, current_end = -1, -1

    for _, item_data in ipairs(sel_items) do
        local s = item_data.start
        local e = item_data.end_
        
        if current_start == -1 then
            current_start = s
            current_end = e
        elseif s <= current_end then
            current_end = math.max(current_end, e)
        else
            table.insert(regions_to_create, {start=current_start, end_=current_end})
            current_start = s
            current_end = e
        end
    end

    if current_start ~= -1 then
        table.insert(regions_to_create, {start=current_start, end_=current_end})
    end

    -- Create Regions
    for i, region_data in ipairs(regions_to_create) do
        local start = region_data.start
        local end_ = region_data.end_
        local n = string.format("%s_%02d", base_name, i)
        reaper.AddProjectMarker(project, 1, start, end_, n, -1)
    end

    reaper.UpdateArrange()
end

----------------------------------------------------------
-- Function: Move Items to Edit Cursor
----------------------------------------------------------
function MoveItemsToEditCursor()
    local cnt = reaper.CountSelectedMediaItems(0)
    if cnt == 0 then return end

    local cursor = reaper.GetCursorPosition()

    local items = {}
    local min_start = math.huge

    for i = 0, cnt - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")

        items[#items+1] = {item=item, pos=pos}
        if pos < min_start then
            min_start = pos
        end
    end

    local offset = cursor - min_start

    local min_new = math.huge
    for i = 1, #items do
        local p = items[i].pos + offset
        if p < min_new then min_new = p end
    end

    if min_new < 0 then
        offset = offset - min_new
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    for i = 1, #items do
        reaper.SetMediaItemInfo_Value(
            items[i].item,
            "D_POSITION",
            items[i].pos + offset
        )
    end

    reaper.PreventUIRefresh(0)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Move items to edit cursor (keep spacing)", -1)
end

----------------------------------------------------------
-- Function: Render Selected Items to Stereo
----------------------------------------------------------
function RenderSelectedItemsToStereo()
    local selItemCount = reaper.CountSelectedMediaItems(0)
    if selItemCount == 0 then
      return
    end

    local sel_start = math.huge
    local sel_end = -math.huge

    for i = 0, selItemCount - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

      sel_start = math.min(sel_start, pos)
      sel_end = math.max(sel_end, pos + len)
    end

    reaper.Undo_BeginBlock()

    local originalTracksMap = {}
    local originalTracksList = {}
    for i = 0, selItemCount - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local tr = reaper.GetMediaItem_Track(item)
      local key = tostring(tr)
      if not originalTracksMap[key] then
        originalTracksMap[key] = true
        table.insert(originalTracksList, tr)
      end
    end

    -- Function: Collect Parents
    local function collectParents(track)
      local parents = {}
      local cur = track
      while true do
        local parent = reaper.GetParentTrack(cur)
        if not parent then break end
        table.insert(parents, parent)
        cur = parent
      end
      return parents
    end

    local targetTracksSet = {}
    local targetTracksOrdered = {}
    for _, tr in ipairs(originalTracksList) do
      local k = tostring(tr)
      if not targetTracksSet[k] then
        targetTracksSet[k] = true
        table.insert(targetTracksOrdered, tr)
      end
      local parents = collectParents(tr)
      for _, p in ipairs(parents) do
        local pk = tostring(p)
        if not targetTracksSet[pk] then
          targetTracksSet[pk] = true
          table.insert(targetTracksOrdered, p)
        end
      end
    end

    -- Function: Track Index
    local function trackIndex(tr)
      return math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
    end
    table.sort(targetTracksOrdered, function(a, b)
      return trackIndex(a) < trackIndex(b)
    end)

    -- Header
    local total = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(total, true)
    local header = reaper.GetTrack(0, total)
    reaper.GetSetMediaTrackInfo_String(header, "P_NAME", "JKK_TEMP_RENDER_HEADER", true)
    reaper.SetMediaTrackInfo_Value(header, "I_FOLDERDEPTH", 1)
    local header_initial_index = reaper.GetMediaTrackInfo_Value(header, "IP_TRACKNUMBER") - 1

    local selectedGUID = {}
    for i = 0, selItemCount - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local ok, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
      if ok then selectedGUID[guid] = true end
    end

    -- Track Orderd
    for _, src in ipairs(targetTracksOrdered) do
      local idx = reaper.CountTracks(0)
      reaper.InsertTrackAtIndex(idx, true)
      local newTr = reaper.GetTrack(0, idx)

      local ok, chunk = reaper.GetTrackStateChunk(src, "", false)
      if ok and chunk then
        reaper.SetTrackStateChunk(newTr, chunk, false)
      end

      local ok2, nm = reaper.GetSetMediaTrackInfo_String(newTr, "P_NAME", "", false)
      local newName = (nm and nm ~= "") and ("JKK_DUP: " .. nm) or "JKK_DUP_TRACK"
      reaper.GetSetMediaTrackInfo_String(newTr, "P_NAME", newName, true)

      local itemCount = reaper.CountTrackMediaItems(newTr)
      for j = itemCount - 1, 0, -1 do
        local it = reaper.GetTrackMediaItem(newTr, j)
        local ok3, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
        if ok3 and guid and not selectedGUID[guid] then
          reaper.DeleteTrackMediaItem(newTr, it)
        end
      end
    end

    -- Footer
    local footerIndex = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(footerIndex, true)
    local footer = reaper.GetTrack(0, footerIndex)
    reaper.GetSetMediaTrackInfo_String(footer, "P_NAME", "JKK_TEMP_RENDER_FOOTER", true)
    reaper.SetMediaTrackInfo_Value(footer, "I_FOLDERDEPTH", -1)

    reaper.UpdateArrange()

    -- Render
    reaper.SetOnlyTrackSelected(header)
    reaper.Main_OnCommand(40788, 0) -- Action ID 40788: Render tracks to stereo stem tracks

    local render_track = reaper.GetTrack(0, header_initial_index)

    if render_track then
      reaper.GetSetMediaTrackInfo_String(
        render_track,
        "P_NAME",
        "JKK_Render Result",
        true
      )

      local render_item_count = reaper.CountTrackMediaItems(render_track)
      if render_item_count > 0 then
        local render_item = reaper.GetTrackMediaItem(render_track, 0)

        local trim_start_pos = sel_start
        local trim_end_pos = sel_end

        if reaper.SplitMediaItem(render_item, trim_end_pos) then
          local next_item = reaper.GetTrackMediaItem(render_track, 1)
          if next_item then
            reaper.DeleteTrackMediaItem(render_track, next_item)
          end
        end

        local current_item = reaper.GetTrackMediaItem(render_track, 0)
        if current_item and reaper.SplitMediaItem(current_item, trim_start_pos) then
          local prev_item = reaper.GetTrackMediaItem(render_track, 0)
          if prev_item then
            reaper.DeleteTrackMediaItem(render_track, prev_item)
          end
        end

        local final_item = reaper.GetTrackMediaItem(render_track, 0)
        if final_item then
          reaper.SetMediaItemInfo_Value(final_item, "D_POSITION", sel_start)
        end
      end
    end

    local current_track_count = reaper.CountTracks(0)

    for i = current_track_count - 1, header_initial_index + 1, -1 do
        local track = reaper.GetTrack(0, i)

        if track then
            local ok, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

            if ok and (name:match("JKK_TEMP_RENDER_HEADER") or name:match("JKK_TEMP_RENDER_FOOTER") or name:match("JKK_DUP:")) then
                reaper.DeleteTrack(track)
            end
        end
    end

    reaper.UpdateArrange()

    reaper.Undo_EndBlock("Duplicate & prune unselected items, Auto-Render, Trim & Rename, AND Auto-Delete (JKK)", -1)
end

----------------------------------------------------------
-- Function: Color Palette 
----------------------------------------------------------
local function SetItemColors(r, g, b)
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then return end

  reaper.Undo_BeginBlock()

  local native_color
  if r == 0 and g == 0 and b == 0 then
    native_color = 0 
  else
    native_color = reaper.ColorToNative(r, g, b) | 0x1000000
  end
  
  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native_color)
  end
  
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Set Item Color", -1)
end

----------------------------------------------------------
-- UI
----------------------------------------------------------
function JKK_ItemTool_Draw(ctx, prev_count, current_count)
    local current_project_state_count = current_count
    
    reaper.ImGui_Text(ctx, 'Select ITEMS before using this feature.')
    -- ========================================================
    reaper.ImGui_SeparatorText(ctx, 'Items Batch Controller')
    
    local changed_vol, changed_pitch, changed_rate
    
    -- Volume Slider
    changed_vol, adjust_vol = reaper.ImGui_SliderDouble(ctx, "Volume", adjust_vol, -30.00, 30.00, "%.2f")
    if reaper.ImGui_IsItemClicked(ctx, 1) then adjust_vol = 0.0; ApplyBatchVolume() end
    
    -- Pitch Slider
    changed_pitch, adjust_pitch = reaper.ImGui_SliderDouble(ctx, "Pitch", adjust_pitch, -12, 12, "%.1f")
    if reaper.ImGui_IsItemClicked(ctx, 1) then adjust_pitch = 0.0; ApplyBatchPitch() end
    
    -- Rate Slider
    changed_rate, adjust_rate = reaper.ImGui_SliderDouble(ctx, "Playback Rate", adjust_rate, 0.25, 4.0, "%.2f")
    if reaper.ImGui_IsItemClicked(ctx, 1) then adjust_rate = 1.0; ApplyBatchRate() end

    -- Call only the function corresponding to the changed slider
    if changed_vol then ApplyBatchVolume() end
    if changed_pitch then ApplyBatchPitch() end
    if changed_rate then ApplyBatchRate() end
    
    -- Group Stretch Ratio Slider
    local changed_group_stretch, new_ratio = reaper.ImGui_SliderDouble(ctx, "Group Stretch", group_stretch_ratio, 0.25, 4.0, "%.2f")
    
    local is_group_stretch_slider_active = reaper.ImGui_IsItemActive(ctx)
    
    if reaper.ImGui_IsItemClicked(ctx, 1) then 
        new_ratio = 1.0
        group_stretch_ratio = 1.0
        ApplyGroupStretch(group_stretch_ratio)
        prev_group_stretch_ratio = 1.0
        update_prev()
    end
    
    if changed_group_stretch then
        group_stretch_ratio = new_ratio
        if group_stretch_ratio ~= prev_group_stretch_ratio then
            ApplyGroupStretch(group_stretch_ratio)
            prev_group_stretch_ratio = group_stretch_ratio
            update_prev()
        end
    end
    
    reaper.ImGui_Spacing(ctx)
    
    if current_project_state_count ~= prev_count and not is_group_stretch_slider_active then
        
        if group_stretch_ratio ~= 1.0 or prev_group_stretch_ratio ~= 1.0 then
            group_stretch_ratio = 1.0
            prev_group_stretch_ratio = 1.0
        end
    end

    -- ========================================================
    reaper.ImGui_SeparatorText(ctx, 'Items Arranger & Randomizer')

    local changed
    -- Start Offset
    changed, start_offset = reaper.ImGui_SliderDouble(ctx, 'Start Offset (Grid)', start_offset, 0, 3, '%.1f')
    start_offset = math.floor(start_offset * 10 + 0.5) / 10
    if reaper.ImGui_IsItemClicked(ctx, 1) then start_offset = 1; apply_spacing_only() end
    if changed then
        apply_spacing_only()
    end

    -- Width
    changed, width = reaper.ImGui_SliderDouble(ctx, 'Width (Grid)', width, 1, 15, '%.0f')
    width = math.floor(width)
    if reaper.ImGui_IsItemClicked(ctx, 1) then width = 5; apply_spacing_only() end
    if changed then
        apply_spacing_only()
    end
    reaper.ImGui_Spacing(ctx)

    -- Position Range
    changed, pos_range = reaper.ImGui_SliderDouble(ctx, 'Pos Range', pos_range, 0, 1.0, '%.3f')
    if reaper.ImGui_IsItemClicked(ctx, 1) then pos_range = 0.0 end
    reaper.ImGui_SameLine(ctx); reaper.ImGui_SameLine(ctx, 0, 33)
    changed, random_pos = reaper.ImGui_Checkbox(ctx, 'Rand##pos', random_pos)

    -- Pitch Range
    changed, pitch_range = reaper.ImGui_SliderDouble(ctx, 'Pitch Range', pitch_range, 0, 24, '%.3f')
    if reaper.ImGui_IsItemClicked(ctx, 1) then pitch_range = 0.0 end
    reaper.ImGui_SameLine(ctx); reaper.ImGui_SameLine(ctx, 0, 25)
    changed, random_pitch = reaper.ImGui_Checkbox(ctx, 'Rand##pitch', random_pitch)

    -- Playback Rate Range
    changed, playback_range = reaper.ImGui_SliderDouble(ctx, 'Playrate Range', playback_range, 0, 24, '%.3f')
    if reaper.ImGui_IsItemClicked(ctx, 1) then playback_range = 0.0 end
    reaper.ImGui_SameLine(ctx)
    changed, random_play = reaper.ImGui_Checkbox(ctx, 'Rand##playback', random_play)

    -- Volume Range
    changed, vol_range = reaper.ImGui_SliderDouble(ctx, 'Vol Range', vol_range, 0, 10, '%.02f')
    if reaper.ImGui_IsItemClicked(ctx, 1) then vol_range = 0.0 end
    reaper.ImGui_SameLine(ctx); reaper.ImGui_SameLine(ctx, 0, 33)
    changed, random_vol = reaper.ImGui_Checkbox(ctx, 'Rand##vol', random_vol)
    reaper.ImGui_Spacing(ctx)
    
    -- Buttons
    if reaper.ImGui_Button(ctx, 'Apply', 80, 22) then
        arrange_items()
        update_prev()
        SaveSettings()
    end
    reaper.ImGui_SameLine(ctx)
    
    if reaper.ImGui_Button(ctx, 'Play/Stop', 80, 22) then
        local is_playing = reaper.GetPlayState() & 1 == 1
        if is_playing then reaper.Main_OnCommand(1016, 0)
        else reaper.Main_OnCommand(40044, 0) end
    end
    reaper.ImGui_SameLine(ctx)

    -- Live Update + Random Order
    changed, live_update = reaper.ImGui_Checkbox(ctx, 'Live Update', live_update)
    reaper.ImGui_SameLine(ctx)
    changed, random_order = reaper.ImGui_Checkbox(ctx, 'Random Arrangement', random_order)
    reaper.ImGui_Spacing(ctx)

    -- ========================================================
    reaper.ImGui_SeparatorText(ctx, 'Actions')
    
    changed, base_name = reaper.ImGui_InputTextMultiline(ctx, ' ', base_name, 292, 22)
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Create Regions', 118, 22) then
        if base_name ~= "" then
            CreateRegionsFromSelectedItems()
        end
    end
    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_Button(ctx, 'Move Items to Edit Cursor', 208, 22) then
        MoveItemsToEditCursor()
    end
    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, 'Render Items to Stereo', 208, 22) then
        RenderSelectedItemsToStereo()
    end
    reaper.ImGui_Spacing(ctx)

    -- ========================================================
    reaper.ImGui_SeparatorText(ctx, 'Item Color Palette')

    local palette_columns = 12
    
    for i, col in ipairs(item_colors) do
      local r, g, b = col[1], col[2], col[3]
      
      local packed_col = reaper.ImGui_ColorConvertDouble4ToU32(r/255, g/255, b/255, 1.0)
      
      reaper.ImGui_PushID(ctx, "col"..i)
      
      if reaper.ImGui_ColorButton(ctx, "##Color", packed_col, 0, 30, 30) then
        SetItemColors(r, g, b)
      end
      
      reaper.ImGui_PopID(ctx)
      
      if i % palette_columns ~= 0 then
        reaper.ImGui_SameLine(ctx)
      end
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_PushID(ctx, "col_default")
    local packed_default_col = reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 1.0)
    if reaper.ImGui_ColorButton(ctx, "##DefaultColor", packed_default_col, 0, 45, 30) then
        SetItemColors(0, 0, 0)
    end
    reaper.ImGui_PopID(ctx)

    -- ========================================================
    local general_state_changed = has_changed()
    
    if general_state_changed then
        if has_range_value_changed() and live_update then
            arrange_items()
        end
        update_prev()
        SaveSettings()
    end
    
end
return {
    JKK_ItemTool_Draw = JKK_ItemTool_Draw,
}