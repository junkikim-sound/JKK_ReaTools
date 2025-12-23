--========================================================
-- @title JKK_ItemTool_Module (Cluster Mode)
-- @author Junki Kim & Modified for Clustering
-- @noindex
--========================================================

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
local slot_stretch_ratio = 1.0
local prev_slot_stretch_ratio = 1.0
local slot_group_base = {}
local last_selected_guids = ""

local width        = 5
local use_edit_cursor = false
local pos_range    = 0
local pitch_range      = 0
local playback_range   = 0
local vol_range        = 0
local current_play_slot = 0

-- Checkbox Default Value
local checkbox_x     = 455
local checkbox_y     = 338
local checkbox_h     = 25
local random_pos     = true
local random_pitch   = true
local random_play    = true
local random_vol     = true
local random_order   = false
local live_update    = true

-- State tracking for selection change and initialization
local prev_project_state_count = reaper.GetProjectStateChangeCount(0) 

-- Save
local prev_width, prev_pos_range = width, pos_range
local prev_pitch_range, prev_playback_range, prev_vol_range = pitch_range, playback_range, vol_range
local prev_random_pos, prev_random_pitch, prev_random_play, prev_random_vol, prev_random_order =
    random_pos, random_pitch, random_play, random_vol, random_order

-- freeze (Cluster IDs based)
local stored_offsets    = {}
local stored_pitch      = {}
local stored_playrates  = {}
local stored_vols       = {}

-- Slot Persistent (Now stores CLUSTERS, not just items)
local persistentClusters = {} 
local anchor_min_pos = nil

-- Regions Renamer
local reaper = reaper
local base_name = ""

-- Color Palette Data
local item_colors = {
  {10,70,57}, {14,96,78},  {21,139,114}, {23,156,128},  {69,171,148},  {162,202,189}, {121,18,19}, {156,23,24},  {168,58,59},  {179,93,93},  {202,162,162}, {221,195,195},
  {10,43,70}, {15,64,104}, {23,96,156},  {102,143,182}, {171,186,207}, {225,230,237}, {88,114,47}, {125,162,67}, {159,206,85}, {184,239,99}, {205,244,152}, {226,248,200},
}

math.randomseed(os.time())

----------------------------------------------------------
-- Icon
----------------------------------------------------------
    local ITEM_ICONS = {}

    local function LoadItemIcons()
        if ITEM_ICONS.loaded then return end
        
        local path = reaper.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Images/"
        
        ITEM_ICONS.fx      = reaper.ImGui_CreateImage(path .. "ITEM_Insert FX @streamline.png")
        ITEM_ICONS.apply   = reaper.ImGui_CreateImage(path .. "ITEM_Random Arrangement @streamline.png")
        ITEM_ICONS.align   = reaper.ImGui_CreateImage(path .. "ITEM_Align Items to Left in Slot @streamline.png")
        ITEM_ICONS.play    = reaper.ImGui_CreateImage(path .. "ITEM_Play @streamline.png")
        ITEM_ICONS.stop    = reaper.ImGui_CreateImage(path .. "ITEM_Stop @streamline.png")
        ITEM_ICONS.move    = reaper.ImGui_CreateImage(path .. "ITEM_Move Items to Edit Cursor @streamline.png")
        ITEM_ICONS.rendtk  = reaper.ImGui_CreateImage(path .. "ITEM_Render Takes @streamline.png")
        ITEM_ICONS.render  = reaper.ImGui_CreateImage(path .. "ITEM_Render Items to Stereo @streamline.png")
        
        ITEM_ICONS.loaded = true
    end

----------------------------------------------------------
-- Function: Batch Item Controller
----------------------------------------------------------
    function ApplyBatchVolume()
        local cnt = reaper.CountSelectedMediaItems(0)
        if cnt == 0 then return end
        reaper.Undo_BeginBlock()

        -- dB를 Linear 값으로 변환
        local linear_vol = 10^(adjust_vol / 20)
        
        for i = 0, cnt - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local take = reaper.GetActiveTake(item)
            
            if take then
                reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", linear_vol)
            end
        end
        
        reaper.UpdateArrange()
        reaper.Undo_EndBlock("Batch Take Volume Applied", -1)
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
                reaper.SetMediaItemInfo_Value(item, "B_PPITCH", 0)
                
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

        local min_pos = math.huge
        local items_data = {}

        for i = 0, cnt - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            if pos < min_pos then min_pos = pos end
            table.insert(items_data, {item=item, pos=pos})
        end

        local stretch_factor = stretch_ratio / prev_group_stretch_ratio

        for _, data in ipairs(items_data) do
            local item = data.item
            local take = reaper.GetActiveTake(item)
            
            local cur_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local cur_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local cur_rate = take and reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0

            local pos_offset = cur_pos - min_pos
            local new_pos = min_pos + (pos_offset * stretch_factor)
            local new_len = cur_len * stretch_factor
            local new_rate = cur_rate / stretch_factor
            
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
            reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)
            if take then reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", new_rate) end
        end
        
        reaper.UpdateArrange()
        reaper.Undo_EndBlock("Group Time Stretch Applied", -1)
    end

----------------------------------------------------------
-- Live Update Check & Settings Load/Save
----------------------------------------------------------
    function has_changed()
        return (
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

    function has_range_value_changed()
        return (
            pos_range    ~= prev_pos_range or
            pitch_range  ~= prev_pitch_range or
            playback_range ~= prev_playback_range or
            vol_range    ~= prev_vol_range
        )
    end

    function update_prev()
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
        local function LoadFlag(namespace, key, default)
            local v = reaper.GetExtState(namespace, key)
            if v == "1" then return true end
            if v == "0" then return false end
            return default
        end

        width = tonumber(reaper.GetExtState("JKK_ItemTool", "width")) or 5.0
        use_edit_cursor = LoadFlag("JKK_ItemTool", "use_edit_cursor", false)
        pos_range = tonumber(reaper.GetExtState("JKK_ItemTool", "pos_range")) or 0.0
        pitch_range = tonumber(reaper.GetExtState("JKK_ItemTool", "pitch_range")) or 0.0
        playback_range = tonumber(reaper.GetExtState("JKK_ItemTool", "playback_range")) or 0.0
        vol_range = tonumber(reaper.GetExtState("JKK_ItemTool", "vol_range")) or 0.0

        random_pos   = LoadFlag("JKK_ItemTool", "random_pos", true)
        random_pitch = LoadFlag("JKK_ItemTool", "random_pitch", true)
        random_play  = LoadFlag("JKK_ItemTool", "random_play", true)
        random_vol   = LoadFlag("JKK_ItemTool", "random_vol", true)
        random_order = LoadFlag("JKK_ItemTool", "random_order", false)
        live_update  = LoadFlag("JKK_ItemTool", "live_update", true)

        update_prev() 
    end

    local function SaveSettings()
        reaper.SetExtState("JKK_ItemTool", "width", tostring(width), true)
        reaper.SetExtState("JKK_ItemTool", "use_edit_cursor", use_edit_cursor and "1" or "0", true)
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
-- Helper Functions: CLUSTERING
----------------------------------------------------------
    local function CollectAndSortSelectedItems()
        local cnt = reaper.CountSelectedMediaItems(0)
        local items = {}
        for i = 0, cnt - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            table.insert(items, {
                item = item,
                pos = pos,
                end_pos = pos + len,
                len = len
            })
        end
        table.sort(items, function(a, b) return a.pos < b.pos end)
        return items
    end

    local function BuildClusters(sorted_items)
        local clusters = {}
        if #sorted_items == 0 then return clusters end

        local epsilon = 0.001 

        local current_cluster = nil

        for i, data in ipairs(sorted_items) do
            if current_cluster == nil then
                current_cluster = {
                    items = {}, 
                    start_pos = data.pos,
                    end_pos = data.end_pos,
                    items_data = {}
                }
                table.insert(current_cluster.items, data.item)
                table.insert(current_cluster.items_data, {
                    item = data.item,
                    rel_pos = 0
                })
            else
                if data.pos < current_cluster.end_pos - epsilon then
                    table.insert(current_cluster.items, data.item)
                    table.insert(current_cluster.items_data, {
                        item = data.item,
                        rel_pos = 0
                    })
                    if data.end_pos > current_cluster.end_pos then
                        current_cluster.end_pos = data.end_pos
                    end
                else
                    table.insert(clusters, current_cluster)
                    
                    current_cluster = {
                        items = {data.item},
                        start_pos = data.pos,
                        end_pos = data.end_pos,
                        items_data = {{item=data.item, rel_pos=0}}
                    }
                end
            end
        end
        if current_cluster then
            table.insert(clusters, current_cluster)
        end

        for _, cluster in ipairs(clusters) do
            for _, item_info in ipairs(cluster.items_data) do
                local actual_pos = reaper.GetMediaItemInfo_Value(item_info.item, "D_POSITION")
                item_info.rel_pos = actual_pos - cluster.start_pos
            end
        end

        return clusters
    end

    local function IsPersistentClustersValid()
        if #persistentClusters == 0 then return false end
        if persistentClusters[1] and persistentClusters[1].items[1] then
            if not reaper.ValidatePtr(persistentClusters[1].items[1], "MediaItem*") then
                return false
            end
        else
            return false
        end
        return true
    end

    local function ShuffleClusters(clusters)
        local shuffled = {}
        for i, v in ipairs(clusters) do shuffled[i] = v end
        for i = #shuffled, 2, -1 do
            local j = math.random(i)
            shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
        end
        return shuffled
    end

----------------------------------------------------------
-- Function: Apply Spacing
----------------------------------------------------------
    function apply_spacing_only()
        local cnt = reaper.CountSelectedMediaItems(0)
        if cnt == 0 then return end

        local base_anchor
        if use_edit_cursor then
            base_anchor = reaper.GetCursorPosition()
        else
            if anchor_min_pos == nil then
                local sorted = CollectAndSortSelectedItems()
                if sorted[1] then anchor_min_pos = sorted[1].pos end
            end
            base_anchor = anchor_min_pos
        end

        local _, grid_size = reaper.GetSetProjectGrid(0, false)
        local start_pos = base_anchor
        local spacing   = grid_size * width * 2

        if not IsPersistentClustersValid() then
             local sorted_items = CollectAndSortSelectedItems()
             persistentClusters = BuildClusters(sorted_items)
        end
        local clusters = persistentClusters

        reaper.Undo_BeginBlock()
        reaper.PreventUIRefresh(1)

        for i, cluster in ipairs(clusters) do
            local cluster_base_pos = start_pos + spacing * (i - 1)
            
            if stored_offsets[i] ~= nil then
                cluster_base_pos = cluster_base_pos + stored_offsets[i]
            end
            
            for _, item_data in ipairs(cluster.items_data) do
                local item = item_data.item
                if reaper.ValidatePtr(item, "MediaItem*") then
                    local new_pos = cluster_base_pos + item_data.rel_pos
                    reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
                end
            end
        end

        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock("Cluster Spacing Updated", -1)
        reaper.UpdateArrange()
        current_play_slot = 0
    end

----------------------------------------------------------
-- Function: Apply Slot Group Stretch
----------------------------------------------------------
    local function GetSelectedItemsGUIDString()
        local guids = {}
        local cnt = reaper.CountSelectedMediaItems(0)
        for i = 0, cnt - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
            table.insert(guids, guid)
        end
        return table.concat(guids, ",")
    end

    function ApplySlotGroupStretch(ratio)
        if not slot_group_base or next(slot_group_base) == nil then return end

        reaper.Undo_BeginBlock()
        reaper.PreventUIRefresh(1)
        
        for item, base in pairs(slot_group_base) do
            if item and reaper.ValidatePtr(item, "MediaItem*") then
                local take = reaper.GetActiveTake(item)
                if take then
                    
                    local new_pos = base.anchor_pos + (base.offset * ratio)
                    local new_len = base.org_len * ratio
                    local new_rate = base.org_rate / ratio

                    reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
                    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)
                    reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", new_rate)
                    reaper.SetMediaItemInfo_Value(item, "B_PPITCH", 0) 
                end
            end
        end

        reaper.PreventUIRefresh(-1)
        reaper.UpdateArrange()
        reaper.Undo_EndBlock("Cluster Stretch Applied", -1)
    end

----------------------------------------------------------
-- Function: Arrange Items Logic (Randomization/Arrangement)
----------------------------------------------------------
    function arrange_items()
        local cnt = reaper.CountSelectedMediaItems(0)
        if cnt == 0 then return end

        local sorted_items = CollectAndSortSelectedItems()
        
        if anchor_min_pos == nil then
            if sorted_items[1] then anchor_min_pos = sorted_items[1].pos end
        end

        local current_random_pos   = random_pos
        local current_random_pitch = random_pitch
        local current_random_play  = random_play
        local current_random_vol   = random_vol
        local current_random_order = random_order

        local _, grid_size = reaper.GetSetProjectGrid(0, false)
        local start_pos = base_anchor or anchor_min_pos
        if use_edit_cursor then start_pos = reaper.GetCursorPosition() end
        
        local spacing   = grid_size * width * 2

        reaper.Undo_BeginBlock()
        reaper.PreventUIRefresh(1)

        -- 1. Create Clusters
        local clusters
        if current_random_order then
            local raw_clusters = BuildClusters(sorted_items)
            clusters = ShuffleClusters(raw_clusters)
            persistentClusters = clusters

            stored_offsets = {}
            stored_pitch = {}
            stored_playrates = {}
            stored_vols = {}
        else
            if not IsPersistentClustersValid() then
                persistentClusters = BuildClusters(sorted_items)
            end
            clusters = persistentClusters
        end

        -- 3. Apply Logic Loop
        for i, cluster in ipairs(clusters) do
            local cluster_base_pos = start_pos + spacing * (i - 1)

            for j, item_data in ipairs(cluster.items_data) do
                local item = item_data.item
                if reaper.ValidatePtr(item, "MediaItem*") then
                    local take = reaper.GetActiveTake(item)
                    local item_key = i .. "_" .. j 

                    local rnd_pitch_val = current_random_pitch and ((math.random() * pitch_range * 2) - pitch_range) or (stored_pitch[item_key] or 0)
                    local rnd_play_rate = current_random_play and (2 ^ (((math.random() * playback_range * 2) - playback_range) / 12)) or (stored_playrates[item_key] or 1.0)
                    local rnd_pos_offset = current_random_pos and ((math.random() * pos_range * 2) - pos_range) or (stored_offsets[item_key] or 0)
                    local rnd_vol_val = stored_vols[item_key] or 1.0
                    if current_random_vol then
                        if vol_range > 0 then
                            local rnd_db = (math.random() * 2.0 - 1.0) * vol_range
                            rnd_vol_val = 10 ^ (rnd_db / 20)
                        else
                            rnd_vol_val = 1.0
                        end
                        stored_vols[item_key] = rnd_vol_val
                    end

                    stored_vols[item_key] = rnd_vol_val
                    stored_pitch[item_key] = rnd_pitch_val
                    stored_playrates[item_key] = rnd_play_rate
                    stored_offsets[item_key] = rnd_pos_offset
                    stored_vols[item_key] = rnd_vol_val

                    if take then
                        reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", rnd_pitch_val)
                        reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", rnd_vol_val)
                        
                        local current_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                        local current_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                        local source_len = current_length * current_rate
                        local new_len = source_len / rnd_play_rate
                        
                        reaper.SetMediaItemLength(item, new_len, true)
                        reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rnd_play_rate)
                    end

                    local final_cluster_pos = cluster_base_pos + rnd_pos_offset
                    local scaled_rel_pos = item_data.rel_pos / rnd_play_rate
                    reaper.SetMediaItemInfo_Value(item, "D_POSITION", final_cluster_pos + scaled_rel_pos)
                end
            end
        end

        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock("Variator (Cluster) Updated", -1)
        reaper.UpdateArrange()
        current_play_slot = 0
    end

----------------------------------------------------------
-- Function: Align Items to Left in Each Slot
----------------------------------------------------------
    function AlignItemsToLeftInSlot()
        if not persistentClusters or #persistentClusters == 0 then
            local sorted_items = CollectAndSortSelectedItems()
            persistentClusters = BuildClusters(sorted_items)
        end

        reaper.Undo_BeginBlock()
        reaper.PreventUIRefresh(1)

        for _, cluster in ipairs(persistentClusters) do
            for _, item_data in ipairs(cluster.items_data) do
                item_data.rel_pos = 0
                if reaper.ValidatePtr(item_data.item, "MediaItem*") then
                    local cluster_pos = reaper.GetMediaItemInfo_Value(item_data.item, "D_POSITION")
                end
            end
        end
        arrange_items()

        reaper.PreventUIRefresh(-1)
        reaper.UpdateArrange()
        reaper.Undo_EndBlock("Align Items to Left in Slot", -1)
    end

----------------------------------------------------------
-- Function: Play Cursor Logic
----------------------------------------------------------
    local function should_reset_slots()
      local sel_cnt = reaper.CountSelectedMediaItems(0)
      if sel_cnt == 0 then return true end
      if not persistentClusters or #persistentClusters == 0 then return true end
      return false
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
        if selItemCount == 0 then return end

        local max_track_idx = 0
        for i = 0, selItemCount - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local tr = reaper.GetMediaItem_Track(item)
            local tr_num = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")
            if tr_num > max_track_idx then max_track_idx = tr_num end
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

        local originalTracksList = {}
        local originalTracksMap = {}
        for i = 0, selItemCount - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local tr = reaper.GetMediaItem_Track(item)
            if not originalTracksMap[tostring(tr)] then
                originalTracksMap[tostring(tr)] = true
                table.insert(originalTracksList, tr)
            end
        end

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

        local targetTracksOrdered = {}
        local targetTracksSet = {}
        for _, tr in ipairs(originalTracksList) do
            local items = {tr, table.unpack(collectParents(tr))}
            for _, t in ipairs(items) do
                if not targetTracksSet[tostring(t)] then
                    targetTracksSet[tostring(t)] = true
                    table.insert(targetTracksOrdered, t)
                end
            end
        end

        table.sort(targetTracksOrdered, function(a, b)
            return reaper.GetMediaTrackInfo_Value(a, "IP_TRACKNUMBER") < reaper.GetMediaTrackInfo_Value(b, "IP_TRACKNUMBER")
        end)

        local total = reaper.CountTracks(0)
        reaper.InsertTrackAtIndex(total, true)
        local header = reaper.GetTrack(0, total)
        reaper.GetSetMediaTrackInfo_String(header, "P_NAME", "JKK_TEMP_HEADER", true)
        reaper.SetMediaTrackInfo_Value(header, "I_FOLDERDEPTH", 1)

        local header_idx = reaper.GetMediaTrackInfo_Value(header, "IP_TRACKNUMBER") - 1

        local selectedGUID = {}
        for i = 0, selItemCount - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
            selectedGUID[guid] = true
        end

        for _, src in ipairs(targetTracksOrdered) do
            local idx = reaper.CountTracks(0)
            reaper.InsertTrackAtIndex(idx, true)
            local newTr = reaper.GetTrack(0, idx)
            local _, chunk = reaper.GetTrackStateChunk(src, "", false)
            reaper.SetTrackStateChunk(newTr, chunk, false)
            
            local _, nm = reaper.GetSetMediaTrackInfo_String(newTr, "P_NAME", "", false)
            reaper.GetSetMediaTrackInfo_String(newTr, "P_NAME", "JKK_DUP:" .. (nm or ""), true)

            for j = reaper.CountTrackMediaItems(newTr) - 1, 0, -1 do
                local it = reaper.GetTrackMediaItem(newTr, j)
                local _, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
                if not selectedGUID[guid] then reaper.DeleteTrackMediaItem(newTr, it) end
            end
        end

        reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
        local footer = reaper.GetTrack(0, reaper.CountTracks(0)-1)
        reaper.GetSetMediaTrackInfo_String(footer, "P_NAME", "JKK_TEMP_FOOTER", true)
        reaper.SetMediaTrackInfo_Value(footer, "I_FOLDERDEPTH", -1)

        reaper.SetOnlyTrackSelected(header)
        reaper.Main_OnCommand(40788, 0) -- Render tracks to stereo stem tracks

        local result_track = reaper.GetTrack(0, header_idx)
        if result_track then
            reaper.GetSetMediaTrackInfo_String(result_track, "P_NAME", "JKK_Render Result", true)
            local r_item = reaper.GetTrackMediaItem(result_track, 0)
            if r_item then
                reaper.SplitMediaItem(r_item, sel_end)
                local next_it = reaper.GetTrackMediaItem(result_track, 1)
                if next_it then reaper.DeleteTrackMediaItem(result_track, next_it) end
                
                local curr_it = reaper.GetTrackMediaItem(result_track, 0)
                if reaper.SplitMediaItem(curr_it, sel_start) then
                    reaper.DeleteTrackMediaItem(result_track, reaper.GetTrackMediaItem(result_track, 0))
                end
                
                local final_it = reaper.GetTrackMediaItem(result_track, 0)
                if final_it then reaper.SetMediaItemInfo_Value(final_it, "D_POSITION", sel_start) end
            end
        end
        for i = reaper.CountTracks(0) - 1, 0, -1 do
            local track = reaper.GetTrack(0, i)
            local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
            if name:match("JKK_TEMP_") or name:match("JKK_DUP:") then
                reaper.DeleteTrack(track)
            end
        end

        if result_track and reaper.ValidatePtr(result_track, "MediaTrack*") then
            reaper.SetOnlyTrackSelected(result_track)
            reaper.ReorderSelectedTracks(max_track_idx, 0)
        end

        reaper.UpdateArrange()
        reaper.Undo_EndBlock("Render Selected Items and Cleanup (JKK)", -1)
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
-- UI_Module 
----------------------------------------------------------
    function JKK_ItemTool_Draw(ctx, prev_count, current_count, shared_info)
        if shared_info.needs_reload then
            ITEM_ICONS.loaded = false
            shared_info.needs_reload = false
        end
        local current_project_state_count = current_count
        if current_count ~= prev_count then
            local current_guids = GetSelectedItemsGUIDString()

            if not reaper.ImGui_IsAnyItemActive(ctx) and current_guids ~= last_selected_guids then
                
                anchor_min_pos = nil
                persistentClusters = {} 
                slot_group_base = {} 
                slot_stretch_ratio = 1.0 
                prev_slot_stretch_ratio = 1.0
                last_selected_guids = current_guids

                local first_item = reaper.GetSelectedMediaItem(0, 0)
                if first_item then
                    local take = reaper.GetActiveTake(first_item)
                    if take then
                        local val_vol = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
                        if val_vol > 0.00000001 then
                            adjust_vol = 20 * (math.log(val_vol) / math.log(10))
                        else
                            adjust_vol = -150.0
                        end
                        if adjust_vol < -30 then adjust_vol = -30 end
                        if adjust_vol > 30 then adjust_vol = 30 end
                        adjust_pitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH")
                        adjust_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                    end
                else
                    adjust_vol = 0.0
                    adjust_pitch = 0.0
                    adjust_rate = 1.0
                end
            end
        end
        
        LoadItemIcons()
        
        reaper.ImGui_Text(ctx, 'Select ITEMS before using this feature.')
        -- ========================================================
        reaper.ImGui_SeparatorText(ctx, 'Items Batch Controller')
            
            local changed_vol, changed_pitch, changed_rate
            
            -- Volume Slider
            changed_vol, adjust_vol = reaper.ImGui_SliderDouble(ctx, "Volume", adjust_vol, -30.00, 30.00, "%.2f")
            if reaper.ImGui_IsItemClicked(ctx, 1) then adjust_vol = 0.0; ApplyBatchVolume() end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_VOL"
            end
            
            -- Pitch Slider
            changed_pitch, adjust_pitch = reaper.ImGui_SliderDouble(ctx, "Pitch", adjust_pitch, -12, 12, "%.1f")
            if reaper.ImGui_IsItemClicked(ctx, 1) then adjust_pitch = 0.0; ApplyBatchPitch() end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_PITCH"
            end
            
            -- Rate Slider
            changed_rate, adjust_rate = reaper.ImGui_SliderDouble(ctx, "Playback Rate", adjust_rate, 0.25, 4.0, "%.2f")
            if reaper.ImGui_IsItemClicked(ctx, 1) then adjust_rate = 1.0; ApplyBatchRate() end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_PLAYRATE"
            end

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
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_GRP_STRTCH"
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
            -- Width
            changed, width = reaper.ImGui_SliderDouble(ctx, 'Slot Interval', width, 1, 15, '%.0f')
            width = math.floor(width)
            if reaper.ImGui_IsItemClicked(ctx, 1) then width = 5; apply_spacing_only() end
            if changed then
                apply_spacing_only()
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_ARR_WIDTH"
            end
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_SetCursorPos(ctx, checkbox_x, checkbox_y - 5 + (checkbox_h * -2))
            _, use_edit_cursor = reaper.ImGui_Checkbox(ctx, 'Cursor', use_edit_cursor)

            -- Slot Stretch Slider Logic
            local changed_slot_stretch, new_slot_ratio =
                reaper.ImGui_SliderDouble(ctx, "Slot Stretch", slot_stretch_ratio, 0.25, 4.0, "%.2f")
            
            if reaper.ImGui_IsItemActivated(ctx) then
                -- Build Clusters if not exists
                if not persistentClusters or #persistentClusters == 0 then
                    local sorted_items = CollectAndSortSelectedItems()
                    persistentClusters = BuildClusters(sorted_items)
                end

                slot_group_base = {}
                
                -- Capture state for Slot Stretch
                for _, cluster in ipairs(persistentClusters) do
                    local current_cluster_start = math.huge
                    for _, item in ipairs(cluster.items) do
                        if reaper.ValidatePtr(item, "MediaItem*") then
                             local p = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                             if p < current_cluster_start then current_cluster_start = p end
                        end
                    end
                    
                    if current_cluster_start == math.huge then current_cluster_start = 0 end

                    for _, item in ipairs(cluster.items) do
                         if reaper.ValidatePtr(item, "MediaItem*") then
                              local take = reaper.GetActiveTake(item)
                              if take then
                                  local cur_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                                  local cur_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                                  local cur_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                                  
                                  slot_group_base[item] = {
                                      anchor_pos = current_cluster_start,
                                      offset     = cur_pos - current_cluster_start,
                                      org_len    = cur_len,
                                      org_rate   = cur_rate
                                  }
                              end
                         end
                    end
                end

                prev_slot_stretch_ratio = 1.0
                slot_stretch_ratio = 1.0
            end

            if changed_slot_stretch then
                slot_stretch_ratio = new_slot_ratio
                ApplySlotGroupStretch(slot_stretch_ratio)
            end

            if reaper.ImGui_IsItemClicked(ctx, 1) then
                slot_stretch_ratio = 1.0
                ApplySlotGroupStretch(1.0)
            end
            
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_ARR_STRTCH"
            end
            reaper.ImGui_Spacing(ctx)

            -- Position Range
            changed, pos_range = reaper.ImGui_SliderDouble(ctx, 'Pos Range', pos_range, 0, 1.0, '%.3f')
            if reaper.ImGui_IsItemClicked(ctx, 1) then pos_range = 0.0 end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_ARR_POS"
            end
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_SetCursorPos(ctx, checkbox_x, checkbox_y + (checkbox_h * 0))
            changed, random_pos = reaper.ImGui_Checkbox(ctx, 'Rand##pos', random_pos)

            -- Pitch Range
            changed, pitch_range = reaper.ImGui_SliderDouble(ctx, 'Pitch Range', pitch_range, 0, 24, '%.3f')
            if reaper.ImGui_IsItemClicked(ctx, 1) then pitch_range = 0.0 end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_ARR_PITCH"
            end
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_SetCursorPos(ctx, checkbox_x, checkbox_y + (checkbox_h * 1))
            changed, random_pitch = reaper.ImGui_Checkbox(ctx, 'Rand##pitch', random_pitch)

            -- Playback Rate Range
            changed, playback_range = reaper.ImGui_SliderDouble(ctx, 'Playrate Range', playback_range, 0, 24, '%.3f')
            if reaper.ImGui_IsItemClicked(ctx, 1) then playback_range = 0.0 end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_ARR_PLAYRATE"
            end
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_SetCursorPos(ctx, checkbox_x, checkbox_y + (checkbox_h * 2))
            changed, random_play = reaper.ImGui_Checkbox(ctx, 'Rand##playback', random_play)

            -- Volume Range
            changed, vol_range = reaper.ImGui_SliderDouble(ctx, 'Vol Range', vol_range, 0, 10, '%.02f')
            if reaper.ImGui_IsItemClicked(ctx, 1) then vol_range = 0.0 end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_ARR_VOL"
            end
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_SetCursorPos(ctx, checkbox_x, checkbox_y + (checkbox_h * 3))
            changed, random_vol = reaper.ImGui_Checkbox(ctx, 'Rand##vol', random_vol)
            reaper.ImGui_Spacing(ctx)
            
            if reaper.ImGui_ImageButton(ctx, "##btn_apply", ITEM_ICONS.apply, 22, 22) then
                arrange_items()
                update_prev()
                SaveSettings()
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_ARR_APPLY"
            end
            reaper.ImGui_SameLine(ctx)

            if reaper.ImGui_ImageButton(ctx, "##btn_align", ITEM_ICONS.align, 22, 22) then
                AlignItemsToLeftInSlot()
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_ARR_ALIGN"
            end
            reaper.ImGui_SameLine(ctx)
            
            if reaper.ImGui_ImageButton(ctx, "##btn_play", ITEM_ICONS.play, 22, 22) then
                local sel_cnt = reaper.CountSelectedMediaItems(0)
                if sel_cnt == 0 then
                    persistentClusters = {}
                    current_play_slot = 0
                    reaper.Main_OnCommand(1007, 0)
                else
                    local max_idx = #persistentClusters
                    if max_idx > 0 then
                        current_play_slot = current_play_slot + 1
                        if current_play_slot > max_idx then
                            current_play_slot = 1
                        end
                        
                        local cluster = persistentClusters[current_play_slot]
                        local target_pos = nil
                        if cluster then
                             for _, item in ipairs(cluster.items) do
                                 if reaper.ValidatePtr(item, "MediaItem*") then
                                      local p = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                                      if not target_pos or p < target_pos then target_pos = p end
                                 end
                             end
                        end

                        if target_pos then
                            reaper.SetEditCurPos(target_pos, true, false)
                            reaper.Main_OnCommand(1007, 0)
                        end
                    else
                        reaper.Main_OnCommand(1007, 0)
                    end
                end
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_ARR_PLAY"
            end
            reaper.ImGui_SameLine(ctx)

            if reaper.ImGui_ImageButton(ctx, "##btn_stop", ITEM_ICONS.stop, 22, 22) then
                reaper.Main_OnCommand(1016, 0)
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_ARR_STOP"
            end
            reaper.ImGui_SameLine(ctx)
            local cx, cy = reaper.ImGui_GetCursorPos(ctx)
            reaper.ImGui_SetCursorPos(ctx, cx, cy + 4)

            -- Live Update + Random Order
            changed, live_update = reaper.ImGui_Checkbox(ctx, 'Live Update', live_update)
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_ARR_LIVE"
            end
            reaper.ImGui_SameLine(ctx)
            cx, cy = reaper.ImGui_GetCursorPos(ctx)
            reaper.ImGui_SetCursorPos(ctx, cx, cy + 5)
            
            changed, random_order = reaper.ImGui_Checkbox(ctx, 'Shuffle Order', random_order)
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_ARR_ARR"
            end
            reaper.ImGui_Spacing(ctx)

        -- ========================================================
        reaper.ImGui_SeparatorText(ctx, 'Actions')

            if reaper.ImGui_ImageButton(ctx, "##btn_move", ITEM_ICONS.move, 22, 22) then
                MoveItemsToEditCursor()
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_MV_EDIT"
            end
            reaper.ImGui_SameLine(ctx)

            if reaper.ImGui_ImageButton(ctx, "##btn_fx", ITEM_ICONS.fx, 22, 22) then
                reaper.Main_OnCommand(40638, 0)
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_INSERT_FX"
            end
            reaper.ImGui_SameLine(ctx)

            if reaper.ImGui_ImageButton(ctx, "##btn_rendtk", ITEM_ICONS.rendtk, 22, 22) then
                reaper.Main_OnCommand(41999, 0)
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_RENDER_TAKE"
            end
            reaper.ImGui_SameLine(ctx)

            if reaper.ImGui_ImageButton(ctx, "##btn_render", ITEM_ICONS.render, 22, 22) then
                RenderSelectedItemsToStereo()
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_RENDER"
            end
            reaper.ImGui_SameLine(ctx)
            
            changed, base_name = reaper.ImGui_InputTextMultiline(ctx, '##BaseName', base_name, 191, 27)
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_CRT_REGION"
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, 'Create Regions', 118, 27) then
                if base_name ~= "" then
                    CreateRegionsFromSelectedItems()
                end
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_CRT_REGION"
            end
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_SetCursorPos(ctx, 0, 550)

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
                if reaper.ImGui_IsItemHovered(ctx) then
                    shared_info.hovered_id = "ITEM_CHNG_COL"
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
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "ITEM_CHNG_COL"
            end
            reaper.ImGui_PopID(ctx)

        -- ========================================================
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then
            reaper.Main_OnCommand(40044, 0)
        end

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