--========================================================
-- @title JKK_Item Manager_Move Items To Mouse Location
-- @author Junki Kim
-- @version 0.5.5
--========================================================

local function get_mouse_position_fallback()
    if reaper.BR_PositionAtMouseCursor ~= nil then
        local ok, pos = pcall(reaper.BR_PositionAtMouseCursor, true)
        if ok and pos ~= nil then return pos end
    end

    if reaper.BR_GetMouseCursorContext_Position ~= nil then
        local ok, pos = pcall(reaper.BR_GetMouseCursorContext_Position)
        if ok and pos ~= nil and pos > -1e12 then return pos end
    end

    return reaper.GetCursorPosition()
end

local function main()
    local cnt = reaper.CountSelectedMediaItems(0)
    if cnt == 0 then
        return
    end

    local mouse_pos = get_mouse_position_fallback()
    if not mouse_pos or type(mouse_pos) ~= "number" then
        return
    end

    local items = {}
    local min_start = math.huge

    for i = 0, cnt - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            items[#items+1] = { item = item, pos = pos }
            if pos < min_start then min_start = pos end
        end
    end

    if min_start == math.huge then
        return
    end

    local offset = mouse_pos - min_start

    local min_new_pos = math.huge
    for i = 1, #items do
        local newpos = items[i].pos + offset
        if newpos < min_new_pos then min_new_pos = newpos end
    end

    if min_new_pos < 0 then
        offset = offset - min_new_pos
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    for i = 1, #items do
        reaper.SetMediaItemInfo_Value(items[i].item, "D_POSITION", items[i].pos + offset)
    end

    reaper.UpdateArrange()
    reaper.PreventUIRefresh(0)
    reaper.Undo_EndBlock("Move items to mouse location (keep spacing, robust)", -1)
end

main()

