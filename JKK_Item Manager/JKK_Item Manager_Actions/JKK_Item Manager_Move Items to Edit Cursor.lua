--========================================================
-- @title JKK_Item Manager_Move Items to Edit Cursor
-- @author Junki Kim
-- @version 1.0.0
--========================================================

function main()
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

main()
