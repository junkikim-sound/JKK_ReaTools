--========================================================
-- @title JKK_Item Manager
-- @author Junki Kim
-- @version 0.9.1
--========================================================

local ctx = reaper.ImGui_CreateContext('JKK_Item Manager')
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

-- Save
local prev_start_offset, prev_width, prev_pos_range = start_offset, width, pos_range
local prev_pitch_range, prev_playback_range, prev_vol_range = pitch_range, playback_range, vol_range
local prev_random_pos, prev_random_pitch, prev_random_play, prev_random_vol, prev_random_order =
    random_pos, random_pitch, random_play, random_vol, random_order

-- freeze
local stored_offsets    = {}  -- item -> offset (seconds)
local stored_pitch      = {}  -- take -> pitch (semitone)
local stored_playrates  = {}  -- take -> playrate
local stored_vols       = {}  -- item -> volume (0..1)

-- Slot Persistent
local persistentSlots = {}

-- Color Palette Data (24 Colors)
local item_colors = {
  {255, 100, 100}, {255, 150, 100}, {255, 200, 100}, {255, 255, 100}, {200, 255, 100}, {100, 255, 100},
  {100, 255, 150}, {100, 255, 200}, {100, 255, 255}, {100, 200, 255}, {100, 150, 255}, {100, 100, 255},
  {150, 100, 255}, {200, 100, 255}, {255, 100, 255}, {255, 100, 200}, {255, 100, 150}, {200, 200, 200},
  {128, 0, 0},     {128, 128, 0},   {0, 128, 0},     {0, 128, 128},   {0, 0, 128},     {128, 0, 128}
}

math.randomseed(os.time())

----------------------------------------------------------
-- Color Palette Function
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
-- JKK_Item Manager_RegionCreate.lua (Integrated)
----------------------------------------------------------
function CreateRegionsFromSelectedItems()
    local project = reaper.EnumProjects(-1, 0)
    if not project then return end

    local sel_items = {}
    local item_count = reaper.CountSelectedMediaItems(project)

    if item_count == 0 then
        return
    end

    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(project, i)
        local start_time = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local end_time = start_time + length
        table.insert(sel_items, {start=start_time, end_=end_time})
    end

    local retval, name_base = reaper.GetUserInputs("Enter Region Name", 1, "Region Name", "New_Region")
    if retval == 0 then
        return
    end

    table.sort(sel_items, function(a, b) return a.start < b.start end)

    local regions_to_create = {}
    local current_start, current_end = -1, -1

    for _, item_data in ipairs(sel_items) do
        local start_time = item_data.start
        local end_time = item_data.end_
        
        if current_start == -1 then
            current_start = start_time
            current_end = end_time
        elseif start_time <= current_end then
            current_end = math.max(current_end, end_time)
        else
            table.insert(regions_to_create, {start=current_start, end_=current_end})
            current_start = start_time
            current_end = end_time
        end
    end

    if current_start ~= -1 then
        table.insert(regions_to_create, {start=current_start, end_=current_end})
    end

    local region_index = 0
    for i, region_data in ipairs(regions_to_create) do
        local start = region_data.start
        local end_ = region_data.end_
        
        local region_num = string.format("_%02d", i)
        local region_name = name_base .. region_num

        reaper.AddProjectMarker(project, 1, start, end_, region_name, 0)
        region_index = region_index + 1
    end

    reaper.UpdateArrange()
end


----------------------------------------------------------
-- Batch Apply Changes
----------------------------------------------------------
function ApplyBatchChanges()
    local cnt = reaper.CountSelectedMediaItems(0)
    if cnt == 0 then return end

    reaper.Undo_BeginBlock()

    for i = 0, cnt - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)

        -- Items Volume
        local linear_vol = 10^(adjust_vol / 20)
        reaper.SetMediaItemInfo_Value(item, "D_VOL", linear_vol)

        -- Items Pitch
        reaper.SetMediaItemTakeInfo_Value(reaper.GetActiveTake(item), "D_PITCH", adjust_pitch)

        -- Items Playback Rate
        reaper.SetMediaItemInfo_Value(item, "B_PPITCH", 0)
        local current_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local current_rate = reaper.GetMediaItemTakeInfo_Value(reaper.GetActiveTake(item), "D_PLAYRATE")

        local take = reaper.GetActiveTake(item)
        if take then
            local source = reaper.GetMediaItemTake_Source(take)
            if source then
                local origin_length = current_length * current_rate
                local adjust_length = origin_length / adjust_rate
                reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", adjust_rate)
                reaper.SetMediaItemLength(item, adjust_length, true)
            end
        end
    end
    reaper.Undo_EndBlock("Batch Item Control applied", -1)
    reaper.UpdateArrange()
end

----------------------------------------------------------
-- Group Time Stretch Logic
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
-- Live Update Check
----------------------------------------------------------
function has_changed()
    return (
        start_offset ~= prev_start_offset or
        width        ~= prev_width or
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

----------------------------------------------------------
-- ExtState Load/Save
----------------------------------------------------------
local function LoadSettings()
    start_offset = tonumber(reaper.GetExtState("JKK_Item Manager", "start_offset")) or 1.0
    width = tonumber(reaper.GetExtState("JKK_Item Manager", "width")) or 5.0
    pos_range = tonumber(reaper.GetExtState("JKK_Item Manager", "pos_range")) or 0.0
    pitch_range = tonumber(reaper.GetExtState("JKK_Item Manager", "pitch_range")) or 0.0
    playback_range = tonumber(reaper.GetExtState("JKK_Item Manager", "playback_range")) or 0.0
    vol_range = tonumber(reaper.GetExtState("JKK_Item Manager", "vol_range")) or 0.0
    
    random_pos = (reaper.GetExtState("JKK_Item Manager", "random_pos") == "1") or true
    random_pitch = (reaper.GetExtState("JKK_Item Manager", "random_pitch") == "1") or true
    random_play = (reaper.GetExtState("JKK_Item Manager", "random_play") == "1") or true
    random_vol = (reaper.GetExtState("JKK_Item Manager", "random_vol") == "1") or true
    random_order = (reaper.GetExtState("JKK_Item Manager", "random_order") == "1") or false
    live_update = (reaper.GetExtState("JKK_Item Manager", "live_update") == "1") or true

    update_prev() 
end

local function SaveSettings()
    reaper.SetExtState("JKK_Item Manager", "start_offset", tostring(start_offset), true)
    reaper.SetExtState("JKK_Item Manager", "width", tostring(width), true)
    reaper.SetExtState("JKK_Item Manager", "pos_range", tostring(pos_range), true)
    reaper.SetExtState("JKK_Item Manager", "pitch_range", tostring(pitch_range), true)
    reaper.SetExtState("JKK_Item Manager", "playback_range", tostring(playback_range), true)
    reaper.SetExtState("JKK_Item Manager", "vol_range", tostring(vol_range), true)
    
    reaper.SetExtState("JKK_Item Manager", "random_pos", random_pos and "1" or "0", true)
    reaper.SetExtState("JKK_Item Manager", "random_pitch", random_pitch and "1" or "0", true)
    reaper.SetExtState("JKK_Item Manager", "random_play", random_play and "1" or "0", true)
    reaper.SetExtState("JKK_Item Manager", "random_vol", random_vol and "1" or "0", true)
    reaper.SetExtState("JKK_Item Manager", "random_order", random_order and "1" or "0", true)
    reaper.SetExtState("JKK_Item Manager", "live_update", live_update and "1" or "0", true)
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
-- Arrange Items Logic
----------------------------------------------------------
function arrange_items()
    local cnt = reaper.CountSelectedMediaItems(0)
    if cnt == 0 then return end

    local only_spacing_changed = (
        (start_offset ~= prev_start_offset or width ~= prev_width) and
        pos_range == prev_pos_range and
        pitch_range == prev_pitch_range and
        playback_range == prev_playback_range and
        vol_range == prev_vol_range and
        random_pos == prev_random_pos and
        random_pitch == prev_random_pitch and
        random_play == prev_random_play and
        random_vol == prev_random_vol and
        random_order == prev_random_order
    )

    local current_random_pos   = random_pos
    local current_random_pitch = random_pitch
    local current_random_play  = random_play
    local current_random_vol   = random_vol
    local current_random_order = random_order

    if only_spacing_changed then
        current_random_pos   = false
        current_random_pitch = false
        current_random_play  = false
        current_random_vol   = false
        current_random_order = false
    end

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

                if current_random_vol then
                    local v = 1.0
                    if vol_range > 0 then
                        v = 1.0 + ((math.random() * 2 - 0.5) * (vol_range / 8) )
                        if v < 0 then v = 0 end
                    end
                    stored_vols[slot_index] = v
                    reaper.SetMediaItemInfo_Value(item, "D_VOL", v)
                else
                    if stored_vols[slot_index] ~= nil then
                        reaper.SetMediaItemInfo_Value(item, "D_VOL", stored_vols[slot_index])
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
-- UI / main loop
----------------------------------------------------------
function main()
    if not open then return end

    -- Increased height from 420 to 620 to fit color palette
    reaper.ImGui_SetNextWindowSize(ctx, 650, 530, reaper.ImGui_Cond_Once())
    style_pop_count, color_pop_count = ApplyTheme(ctx)
    
    local visible, open_flag = reaper.ImGui_Begin(ctx, 'JKK_Item Manager', open,
        reaper.ImGui_WindowFlags_NoCollapse())

    if visible then        
        -- ========================================================
        reaper.ImGui_SeparatorText(ctx, 'Item Batch Controller')
        
        local changed_vol, changed_pitch, changed_rate
        
        -- Volume Slider
        changed_vol, adjust_vol = reaper.ImGui_SliderDouble(ctx, "Items Volume", adjust_vol, -30.00, 30.00, "%.2f")
        if reaper.ImGui_IsItemClicked(ctx, 1) then adjust_vol = 0.0; ApplyBatchChanges() end
        
        -- Pitch Slider
        changed_pitch, adjust_pitch = reaper.ImGui_SliderDouble(ctx, "Items Pitch", adjust_pitch, -12, 12, "%.1f")
        if reaper.ImGui_IsItemClicked(ctx, 1) then adjust_pitch = 0.0; ApplyBatchChanges() end
        
        -- Rate Slider
        changed_rate, adjust_rate = reaper.ImGui_SliderDouble(ctx, "Items Playback Rate", adjust_rate, 0.25, 4.0, "%.2f")
        if reaper.ImGui_IsItemClicked(ctx, 1) then adjust_rate = 1.0; ApplyBatchChanges() end

        -- Update
        if changed_vol or changed_pitch or changed_rate then
            ApplyBatchChanges()
        end
        
        -- Group Stretch Ratio Slider
        local changed_group_stretch, new_ratio = reaper.ImGui_SliderDouble(ctx, "Group Stretch Factor", group_stretch_ratio, 0.25, 4.0, "%.2f")
        
        if reaper.ImGui_IsItemClicked(ctx, 1) then 
            new_ratio = 1.0
            group_stretch_ratio = 1.0
            ApplyGroupStretch(group_stretch_ratio)
            update_prev()
        end
        
        if changed_group_stretch then
            group_stretch_ratio = new_ratio
            if group_stretch_ratio ~= prev_group_stretch_ratio then
                ApplyGroupStretch(group_stretch_ratio)
                update_prev()
            end
        end
        
        reaper.ImGui_Spacing(ctx)

        -- ========================================================
        reaper.ImGui_SeparatorText(ctx, 'Item Arranger & Randomizer')
        reaper.ImGui_Spacing(ctx)

        local changed
        -- Start Offset
        changed, start_offset = reaper.ImGui_SliderDouble(ctx, 'Start Offset (Grid)', start_offset, 0, 3, '%.1f')
        start_offset = math.floor(start_offset * 10 + 0.5) / 10
        if reaper.ImGui_IsItemClicked(ctx, 1) then start_offset = 1 end

        -- Width
        changed, width = reaper.ImGui_SliderDouble(ctx, 'Width (Grid)', width, 1, 15, '%.0f')
        width = math.floor(width)
        if reaper.ImGui_IsItemClicked(ctx, 1) then width = 5 end
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

        -- Live Update + Random Order
        changed, live_update = reaper.ImGui_Checkbox(ctx, 'Live Update', live_update)
        reaper.ImGui_SameLine(ctx)
        changed, random_order = reaper.ImGui_Checkbox(ctx, 'Random Arrangement', random_order)
        reaper.ImGui_Spacing(ctx)
        
        -- ========================================================
        reaper.ImGui_SeparatorText(ctx, 'Actions')

        -- Buttons
        if reaper.ImGui_Button(ctx, 'Apply', 70, 35) then
            arrange_items()
            update_prev()
            SaveSettings()
        end
        
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_Button(ctx, 'Play/Stop', 70, 35) then
            local is_playing = reaper.GetPlayState() & 1 == 1
            if is_playing then reaper.Main_OnCommand(1016, 0)
            else reaper.Main_OnCommand(40044, 0) end
        end

        reaper.ImGui_SameLine(ctx, 0, 53)
        
        if reaper.ImGui_Button(ctx, 'Regions Creator', 100, 35) then
            CreateRegionsFromSelectedItems()
        end
        
        reaper.ImGui_Spacing(ctx)

        -- ========================================================
        reaper.ImGui_SeparatorText(ctx, 'Item Color Palette')

        local palette_columns = 12
        
        for i, col in ipairs(item_colors) do
          local r, g, b = col[1], col[2], col[3]
          
          -- Packed Integer for ColorButton
          local packed_col = reaper.ImGui_ColorConvertDouble4ToU32(r/255, g/255, b/255, 1.0)
          
          reaper.ImGui_PushID(ctx, "col"..i)
          
          -- Color Button (Size 30x30)
          if reaper.ImGui_ColorButton(ctx, "##Color", packed_col, 0, 30, 30) then
            SetItemColors(r, g, b)
          end
          
          reaper.ImGui_PopID(ctx)
          
          -- Layout: SameLine if not the last column
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
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, "Set Default")
        reaper.ImGui_PopID(ctx)

        -- Live refresh logic for Arranger
        if has_changed() then
            if live_update then
                arrange_items()
            end
            update_prev()
            SaveSettings()
        end

        reaper.ImGui_PopStyleVar(ctx, style_pop_count)
        reaper.ImGui_PopStyleColor(ctx, color_pop_count)
        reaper.ImGui_End(ctx)
    else
        reaper.ImGui_End(ctx)
    end

    open = open_flag
    if open then reaper.defer(main) end
end

main()