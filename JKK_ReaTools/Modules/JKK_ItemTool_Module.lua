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
local stored_offsets    = {} -- Key: Cluster ID or Index
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

        -- Use a simpler approach for group stretch: Min Pos
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
    
    -- 선택된 모든 아이템을 수집하고 시간순으로 정렬
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
        -- Start Position 기준으로 정렬
        table.sort(items, function(a, b) return a.pos < b.pos end)
        return items
    end

    -- 정렬된 아이템 리스트를 받아 Cluster(겹치는 그룹) 생성
    local function BuildClusters(sorted_items)
        local clusters = {}
        if #sorted_items == 0 then return clusters end

        -- Tolerance (1ms)
        local epsilon = 0.001 

        local current_cluster = nil

        for i, data in ipairs(sorted_items) do
            if current_cluster == nil then
                -- 새로운 클러스터 시작
                current_cluster = {
                    items = {}, 
                    start_pos = data.pos,
                    end_pos = data.end_pos,
                    items_data = {} -- 내부 아이템 정보 (상대 오프셋 등)
                }
                table.insert(current_cluster.items, data.item)
                table.insert(current_cluster.items_data, {
                    item = data.item,
                    rel_pos = 0 -- 첫 아이템은 기준점이 됨 (하지만 나중에 start_pos 기준으로 다시 계산)
                })
            else
                -- 겹치는지 확인 (현재 클러스터의 끝지점 vs 새 아이템의 시작점)
                if data.pos < current_cluster.end_pos - epsilon then
                    -- 겹침: 클러스터에 추가
                    table.insert(current_cluster.items, data.item)
                    table.insert(current_cluster.items_data, {
                        item = data.item,
                        rel_pos = 0 -- 임시
                    })
                    -- 클러스터 끝지점 갱신
                    if data.end_pos > current_cluster.end_pos then
                        current_cluster.end_pos = data.end_pos
                    end
                else
                    -- 안 겹침: 기존 클러스터 종료 및 저장
                    table.insert(clusters, current_cluster)
                    
                    -- 새 클러스터 시작
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

        -- 클러스터 내부 상대 위치(Offset) 확정 계산
        for _, cluster in ipairs(clusters) do
            for _, item_info in ipairs(cluster.items_data) do
                local actual_pos = reaper.GetMediaItemInfo_Value(item_info.item, "D_POSITION")
                item_info.rel_pos = actual_pos - cluster.start_pos
            end
        end

        return clusters
    end

    -- 저장된 클러스터 상태가 유효한지 확인
    local function IsPersistentClustersValid()
        if #persistentClusters == 0 then return false end
        -- 첫번째 아이템이 유효한지 정도만 체크
        if persistentClusters[1] and persistentClusters[1].items[1] then
            if not reaper.ValidatePtr(persistentClusters[1].items[1], "MediaItem*") then
                return false
            end
        else
            return false
        end
        return true
    end

    -- 클러스터 목록 섞기 (Fisher-Yates)
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
-- Function: Apply Spacing (Cluster Based)
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

        -- Get Clusters
        if not IsPersistentClustersValid() then
             local sorted_items = CollectAndSortSelectedItems()
             persistentClusters = BuildClusters(sorted_items)
        end
        local clusters = persistentClusters

        reaper.Undo_BeginBlock()
        reaper.PreventUIRefresh(1)

        for i, cluster in ipairs(clusters) do
            local cluster_base_pos = start_pos + spacing * (i - 1)
            
            -- 클러스터 오프셋 적용 (Freeze된 값이 있으면 사용)
            if stored_offsets[i] ~= nil then
                cluster_base_pos = cluster_base_pos + stored_offsets[i]
            end
            
            -- 클러스터 내부 아이템 이동
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
-- Function: Apply Slot Group Stretch (Cluster Based)
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

        -- slot_group_base는 이제 item key가 아니라 {item=item, org_pos=..., org_len=...} 정보를 담고 있음
        -- 클러스터의 Start Pos 기준으로 늘려야 함.
        
        -- 하지만 여기서는 개별 아이템의 본래 위치/길이를 기억했다가 Ratio만 곱해주는게 아니라,
        -- "클러스터 시작점"을 기준으로 위치가 늘어나야 함.
        
        -- 구조: slot_group_base[item] = { cluster_start_pos, offset_from_cluster, org_len, org_rate }
        
        for item, base in pairs(slot_group_base) do
            if item and reaper.ValidatePtr(item, "MediaItem*") then
                local take = reaper.GetActiveTake(item)
                if take then
                    -- 새 위치 = 클러스터 시작점 + (원래 오프셋 * 비율)
                    -- 주의: 클러스터 시작점 자체는 변하지 않음 (Stretch는 제자리에서 늘어나는 것)
                    -- 하지만 Spacing에 의해 클러스터가 이동했을 수 있음.
                    -- 현재 로직상 Slot Stretch는 "Spacing 완료 후" 적용된다고 가정.
                    -- 따라서 item의 현재 클러스터 시작점을 다시 구하거나, 저장된 값을 써야함.
                    -- 여기서는 저장된 base.anchor_pos(클러스터 시작점)을 씁니다.
                    
                    -- *중요*: 이미 Spacing 등으로 아이템이 이동했을 수 있음. 
                    -- Stretch는 "Cluster 내부"를 늘리는 것.
                    -- 따라서 현재 Cluster의 StartPos는 유지되어야 함.
                    -- 그러나 로직의 단순화를 위해, slot_group_base 생성 시점의 anchor_pos를 사용하면
                    -- Spacing -> Stretch 순서일 때 Spacing 위치가 무시될 위험이 있음.
                    
                    -- 해결책: Slot Stretch는 보통 Spacing과는 독립적(내부 길이 조절).
                    -- 현재 아이템의 위치를 기준으로 하지 않고, 저장된 anchor 기준 비율 계산.
                    
                    -- 로직 수정: 사용자가 슬라이더를 잡았을 때(activated) 현재 위치를 기준으로 base를 캡처함.
                    -- 따라서 base.anchor_pos는 "현재 화면상의 클러스터 시작점"임.
                    
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

        -- 1. 클러스터 생성 (혹은 재활용)
        -- Random Order가 켜져있으면 매번 새로 생성해서 섞어야 함.
        -- 하지만 Freeze 기능을 위해 persistentClusters를 유지해야 할 수도 있음.
        -- 여기서는 로직을 단순화: 버튼 누르면 무조건 다시 계산 (하지만 옵션 체크)
        
        local clusters
        if current_random_order then
            -- 셔플 모드면 새로 만들고 섞음
            local raw_clusters = BuildClusters(sorted_items)
            clusters = ShuffleClusters(raw_clusters)
            persistentClusters = clusters -- 순서 저장
            
            -- 순서가 바뀌었으므로 저장된 랜덤값(stored_*)들도 초기화 혹은 매핑 이슈 발생
            -- 순서 셔플 시에는 새로운 랜덤성을 부여하는 것이 자연스러움 -> stored 초기화
            stored_offsets = {}
            stored_pitch = {}
            stored_playrates = {}
            stored_vols = {}
        else
            -- 순서 유지 모드
            if not IsPersistentClustersValid() then
                persistentClusters = BuildClusters(sorted_items)
            end
            clusters = persistentClusters
        end

        -- 2. Freeze Logic (체크박스 해제 시 값 보존)
        -- 클러스터 단위로 저장해야 함. stored_pitch[cluster_index]
        -- 하지만 코드 복잡도를 줄이기 위해, "랜덤이 꺼지면 -> 저장된 값 사용" 로직 유지.
        
        -- 저장 로직: 현재 상태를 저장할 필요가 있을까? 
        -- 이미 아래 Loop에서 생성하면서 저장함. 
        -- 여기서는 "꺼졌을 때" 복원할 값이 없으면 현재 값을 읽어오는 로직만 필요.
        -- 기존 코드는 items iteration 돌면서 읽어왔음. 클러스터 모드에서도 비슷하게.

        -- 3. Apply Logic Loop
        for i, cluster in ipairs(clusters) do
            
            -- A. Random Values Generation (Cluster Scope)
            local rnd_pitch_val = 0
            local rnd_play_rate = 1.0
            local rnd_pos_offset = 0
            local rnd_vol_val = 1.0

            -- Pitch
            if current_random_pitch then
                rnd_pitch_val = (math.random() * pitch_range * 2) - pitch_range
                stored_pitch[i] = rnd_pitch_val
            else
                if stored_pitch[i] ~= nil then rnd_pitch_val = stored_pitch[i] end
            end

            -- Playrate
            if current_random_play then
                local rnd = (math.random() * playback_range * 2) - playback_range
                rnd_play_rate = 2 ^ (rnd / 12)
                stored_playrates[i] = rnd_play_rate
            else
                if stored_playrates[i] ~= nil then rnd_play_rate = stored_playrates[i] end
            end

            -- Position Offset
            if current_random_pos then
                rnd_pos_offset = (math.random() * pos_range * 2) - pos_range
                stored_offsets[i] = rnd_pos_offset
            else
                if stored_offsets[i] ~= nil then rnd_pos_offset = stored_offsets[i] end
            end

            -- Volume
            if current_random_vol then
                if vol_range > 0 then
                    rnd_vol_val = 1.0 + ((math.random() * 2 - 0.5) * (vol_range / 8) ) 
                    if rnd_vol_val < 0 then rnd_vol_val = 0 end
                end
                stored_vols[i] = rnd_vol_val
            else
                if stored_vols[i] ~= nil then rnd_vol_val = stored_vols[i] end
            end

            -- B. Apply to Items in Cluster
            local cluster_base_pos = start_pos + spacing * (i - 1)
            local final_cluster_pos = cluster_base_pos + rnd_pos_offset

            for _, item_data in ipairs(cluster.items_data) do
                local item = item_data.item
                if reaper.ValidatePtr(item, "MediaItem*") then
                    local take = reaper.GetActiveTake(item)
                    
                    -- Pitch
                    if take then
                         reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", rnd_pitch_val)
                    end

                    -- Playrate & Length
                    -- Playrate가 변하면 길이도 변하므로, 겹쳐진 아이템들의 '간격(Offset)'도 
                    -- 같은 비율로 변해야 찢어지지 않고 한 덩어리처럼 보입니다.
                    if take then
                         local current_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                         local current_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                         
                         -- 1. 원본 소스 길이 계산 (Rate 1.0 기준)
                         local source_len = current_length * current_rate
                         
                         -- 2. 새로운 길이 계산
                         local new_len = source_len / rnd_play_rate
                         
                         reaper.SetMediaItemLength(item, new_len, true)
                         reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rnd_play_rate)
                    end

                    -- Position (Anchor Logic Fix)
                    -- [수정됨] Slot Stretch 로직과 동일한 원리 적용
                    -- Playrate가 빨라지면(값 증가), 길이는 짧아지고 간격도 좁아져야 함 (반비례)
                    -- 따라서 원래의 상대 위치(rel_pos)를 rnd_play_rate로 나누어 줍니다.
                    
                    local scaled_rel_pos = item_data.rel_pos / rnd_play_rate
                    local new_pos = final_cluster_pos + scaled_rel_pos
                    
                    reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)

                    -- Volume
                    if take then
                        reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", rnd_vol_val)
                        -- reaper.SetMediaItemInfo_Value(item, "D_VOL", 1.0)
                    end
                end
            end
        end

        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock("Variator (Cluster) Updated", -1)
        reaper.UpdateArrange()
        current_play_slot = 0
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
-- Function: Move Items to Edit Cursor (Cluster Logic Needed?)
----------------------------------------------------------
    -- 이 기능은 "Keep Spacing"이므로 단순 이동. 클러스터 로직 없어도 됨.
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

        ----------------------------------------------------------
        -- [추가됨] 0. Find the lowest track index involved (Target Position)
        ----------------------------------------------------------
        local max_track_idx = 0
        for i = 0, selItemCount - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local tr = reaper.GetMediaItem_Track(item)
            local tr_num = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") -- 1-based
            if tr_num > max_track_idx then max_track_idx = tr_num end
        end

        ----------------------------------------------------------
        -- 1. Calculate the total time range
        ----------------------------------------------------------
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

        ----------------------------------------------------------
        -- 2. Collect tracks and their parent folders
        ----------------------------------------------------------
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

        ----------------------------------------------------------
        -- 3. Create temporary structure
        ----------------------------------------------------------
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

        ----------------------------------------------------------
        -- 4. Perform Render and Post-processing
        ----------------------------------------------------------
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

        ----------------------------------------------------------
        -- 5. Final Cleanup & Move Result Track
        ----------------------------------------------------------
        for i = reaper.CountTracks(0) - 1, 0, -1 do
            local track = reaper.GetTrack(0, i)
            local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
            if name:match("JKK_TEMP_") or name:match("JKK_DUP:") then
                reaper.DeleteTrack(track)
            end
        end

        -- [추가됨] 결과 트랙을 원본 선택 영역의 바로 아래로 이동
        if result_track and reaper.ValidatePtr(result_track, "MediaTrack*") then
            reaper.SetOnlyTrackSelected(result_track)
            -- max_track_idx는 1-based index (Track Number)입니다.
            -- ReorderSelectedTracks의 첫 번째 인자는 "Target Index (Insert Before)"입니다.
            -- Track 5번 뒤에 넣고 싶으면, Index 5 (Track 6번 자리)에 넣어야 합니다.
            -- 따라서 max_track_idx 값을 그대로 사용하면 됩니다.
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

            -- 사용자가 슬라이더를 드래그 중이 아닐 때만 업데이트 (드래그 중 값 튀는 현상 방지)
            if not reaper.ImGui_IsAnyItemActive(ctx) and current_guids ~= last_selected_guids then
                
                -- 1. 기존 초기화 로직
                anchor_min_pos = nil
                persistentClusters = {} 
                slot_group_base = {} 
                slot_stretch_ratio = 1.0 
                prev_slot_stretch_ratio = 1.0
                last_selected_guids = current_guids

                -- 2. [추가됨] 첫 번째 아이템의 값 가져와서 슬라이더 동기화
                local first_item = reaper.GetSelectedMediaItem(0, 0)
                if first_item then
                    local take = reaper.GetActiveTake(first_item)
                    if take then
                        -- Volume: Linear(1.0) -> dB(0.0) 변환 필요
                        local val_vol = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
                        if val_vol > 0.00000001 then -- log(0) 방지
                            adjust_vol = 20 * (math.log(val_vol) / math.log(10))
                        else
                            adjust_vol = -150.0 -- -inf
                        end
                        -- 슬라이더 범위(-30 ~ 30)에 맞춰 클램핑
                        if adjust_vol < -30 then adjust_vol = -30 end
                        if adjust_vol > 30 then adjust_vol = 30 end

                        -- Pitch
                        adjust_pitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH")

                        -- Playrate
                        adjust_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                    end
                else
                    -- 선택된 게 없으면 기본값으로 리셋 (선택 사항)
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

            -- Slot Stretch Slider Logic (Cluster Modified)
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
                    -- 현재 화면상의 클러스터 시작점 찾기 (Spacing 등이 적용된 상태일 수 있으므로)
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
                                      anchor_pos = current_cluster_start, -- 이 아이템이 속한 클러스터의 현재 시작점
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
            
            if reaper.ImGui_ImageButton(ctx, "##btn_play", ITEM_ICONS.play, 22, 22) then
                local sel_cnt = reaper.CountSelectedMediaItems(0)
                if sel_cnt == 0 then
                    persistentClusters = {}
                    current_play_slot = 0
                    reaper.Main_OnCommand(1007, 0)
                else
                    -- Cluster Loop Play
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