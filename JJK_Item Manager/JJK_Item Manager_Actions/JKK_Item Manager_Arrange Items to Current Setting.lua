--========================================================
-- @title JKK_Item Manager_Arrange Items to Current Setting
-- @author Junki Kim
-- @version 1.0.1
--========================================================

local EXTSTATE_KEY = "JKK_Item Manager"

local function LoadSettings()
    local S = {}
    S.start_offset = tonumber(reaper.GetExtState(EXTSTATE_KEY, "start_offset")) or 1.0
    S.width = tonumber(reaper.GetExtState(EXTSTATE_KEY, "width")) or 5.0
    S.pos_range = tonumber(reaper.GetExtState(EXTSTATE_KEY, "pos_range")) or 0.0
    S.pitch_range = tonumber(reaper.GetExtState(EXTSTATE_KEY, "pitch_range")) or 0.0
    S.playback_range = tonumber(reaper.GetExtState(EXTSTATE_KEY, "playback_range")) or 0.0
    S.vol_range = tonumber(reaper.GetExtState(EXTSTATE_KEY, "vol_range")) or 0.0
    
    S.random_pos = (reaper.GetExtState(EXTSTATE_KEY, "random_pos") == "1") or true
    S.random_pitch = (reaper.GetExtState(EXTSTATE_KEY, "random_pitch") == "1") or true
    S.random_play = (reaper.GetExtState(EXTSTATE_KEY, "random_play") == "1") or true
    S.random_vol = (reaper.GetExtState(EXTSTATE_KEY, "random_vol") == "1") or true
    S.random_order = (reaper.GetExtState(EXTSTATE_KEY, "random_order") == "1") or false
    
    return S
end

local settings = LoadSettings()

local start_offset = settings.start_offset
local width = settings.width
local pos_range = settings.pos_range
local pitch_range = settings.pitch_range
local playback_range = settings.playback_range
local vol_range = settings.vol_range

local random_pos = settings.random_pos
local random_pitch = settings.random_pitch
local random_play = settings.random_play
local random_vol = settings.random_vol
local random_order = settings.random_order

local stored_offsets    = {}  
local stored_pitch      = {}  
local stored_playrates  = {}  
local stored_vols       = {}  
local persistentSlots   = {} 
local prev_random_pitch = random_pitch
local prev_random_play  = random_play  
local prev_random_vol   = random_vol   

math.randomseed(os.time())


local function generate_random_slots(items, max_count)
    local slots = {}
    for i = 1, max_count do slots[i] = nil end

    for _, item in ipairs(items) do
        local idx
        repeat
            idx = math.random(1, max_count)
        until slots[idx] == nil
        slots[idx] = item
    end

    return slots
end

local function create_default_slots(items, max_count)
    local slots = {}
    for i = 1, max_count do slots[i] = items[i] or nil end
    return slots
end


function arrange_items()
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

    for track, items in pairs(track_items) do
        table.sort(items, function(a, b)
            return reaper.GetMediaItemInfo_Value(a, "D_POSITION")
                <  reaper.GetMediaItemInfo_Value(b, "D_POSITION")
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

        if random_order then
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

        if prev_random_pitch and not random_pitch then
            for slot_index = 1, max_count do
                local item = slots[slot_index]
                if item then
                    local take = reaper.GetActiveTake(item)
                    if take then
                        stored_pitch[take] = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH")
                    end
                end
            end
        end

        if prev_random_play and not random_play then
            for slot_index = 1, max_count do
                local item = slots[slot_index]
                if item then
                    local take = reaper.GetActiveTake(item)
                    if take then
                        stored_playrates[take] = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                    end
                end
            end
        end

        if prev_random_vol and not random_vol then
            for slot_index = 1, max_count do
                local item = slots[slot_index]
                if item then
                    stored_vols[item] = reaper.GetMediaItemInfo_Value(item, "D_VOL")
                end
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
                    if random_pitch then
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
                    if random_play then
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

                if random_pos then
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

                -- Volume
                if random_vol then
                    local v = 1.0
                    if vol_range > 0 then
                        v = 1.0 + ((math.random() * 2 - 0.5) * (vol_range / 8) )
                        if v < 0 then v = 0 end
                    end

                    stored_vols[item] = v
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
    reaper.Undo_EndBlock("Variator Quick Apply", -1)
    reaper.UpdateArrange()
end

reaper.defer(arrange_items)