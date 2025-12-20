--========================================================
-- @title JKK_ItemTool_Apply Current Setting to Items
-- @author Junki Kim
-- @version 0.6.3
--========================================================

local EXTSTATE_KEY = "JKK_ItemTool"

local function LoadSettings()
    local function LoadFlag(key, default)
        local v = reaper.GetExtState(EXTSTATE_KEY, key)
        if v == "1" then return true end
        if v == "0" then return false end
        return default
    end

    local S = {}
    S.width = tonumber(reaper.GetExtState(EXTSTATE_KEY, "width")) or 5.0
    S.use_edit_cursor = LoadFlag("use_edit_cursor", false)
    S.pos_range = tonumber(reaper.GetExtState(EXTSTATE_KEY, "pos_range")) or 0.0
    S.pitch_range = tonumber(reaper.GetExtState(EXTSTATE_KEY, "pitch_range")) or 0.0
    S.playback_range = tonumber(reaper.GetExtState(EXTSTATE_KEY, "playback_range")) or 0.0
    S.vol_range = tonumber(reaper.GetExtState(EXTSTATE_KEY, "vol_range")) or 0.0
    
    S.random_pos = LoadFlag("random_pos", true)
    S.random_pitch = LoadFlag("random_pitch", true)
    S.random_play = LoadFlag("random_play", true)
    S.random_vol = LoadFlag("random_vol", true)
    S.random_order = LoadFlag("random_order", false)
    
    return S
end

local settings = LoadSettings()

function arrange_items()
    local cnt = reaper.CountSelectedMediaItems(0)
    if cnt == 0 then return end

    local anchor_pos_str = reaper.GetExtState(EXTSTATE_KEY, "anchor_pos")
    local anchor_pos = tonumber(anchor_pos_str)

    if settings.use_edit_cursor then
        anchor_pos = reaper.GetCursorPosition()
    elseif not anchor_pos then
        local min = math.huge
        for i = 0, cnt - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            if pos < min then min = pos end
        end
        anchor_pos = reaper.SnapToGrid(0, min)
        reaper.SetExtState(EXTSTATE_KEY, "anchor_pos", tostring(anchor_pos), false)
    end

    local _, grid_size = reaper.GetSetProjectGrid(0, false)
    local start_pos = anchor_pos
    local spacing = grid_size * settings.width * 2

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

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    math.randomseed(os.time())

    for track, items in pairs(track_items) do
        local active_items = items
        if settings.random_order then
            local shuffled = {}
            local temp = {table.unpack(items)}
            while #temp > 0 do
                table.insert(shuffled, table.remove(temp, math.random(#temp)))
            end
            active_items = shuffled
        end

        for i, item in ipairs(active_items) do
            local take = reaper.GetActiveTake(item)
            
            -- Pitch
            if take and settings.random_pitch then
                reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", (math.random()*settings.pitch_range*2)-settings.pitch_range)
            end

            -- Playrate & Length
            if take and settings.random_play then
                local rate = 2 ^ (((math.random()*settings.playback_range*2)-settings.playback_range) / 12)
                local cur_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local cur_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                reaper.SetMediaItemLength(item, (cur_len * cur_rate) / rate, true)
                reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
            end

            local base_pos = start_pos + (spacing * (i - 1))
            local final_pos = base_pos

            if settings.random_pos then
                final_pos = base_pos + (math.random() * settings.pos_range * 2) - settings.pos_range
            end
            
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", final_pos)

            -- Volume
            if settings.random_vol then
                local v = 1.0 + ((math.random() * 2 - 0.5) * (settings.vol_range / 8))
                reaper.SetMediaItemInfo_Value(item, "D_VOL", math.max(0, v))
            end
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Variator Apply Current", -1)
    reaper.UpdateArrange()
end

reaper.defer(arrange_items)