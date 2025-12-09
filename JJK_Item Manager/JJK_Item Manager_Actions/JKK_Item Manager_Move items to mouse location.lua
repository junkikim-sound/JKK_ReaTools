-- Move Items to Mouse Location (robust mouse position, keep relative spacing)
-- 작성자: Jungi Kim (수정본)
-- 설명: 여러 아이템 선택 시, 선택된 아이템들의 맨 앞 아이템 시작 지점을 마우스 위치로 이동시키고
--       나머지 아이템들은 그 간격을 유지하도록 이동시킵니다.
--       SWS/BR 함수가 없는 환경에도 편집 커서 위치를 fallback으로 사용합니다.

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
        reaper.ShowMessageBox("선택된 아이템이 없습니다.", "Move items to mouse", 0)
        return
    end

    local mouse_pos = get_mouse_position_fallback()
    if not mouse_pos or type(mouse_pos) ~= "number" then
        reaper.ShowMessageBox("마우스 위치를 얻지 못했습니다.\n(편집 커서를 사용하세요)", "Move items to mouse", 0)
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
        reaper.ShowMessageBox("아이템 위치를 읽을 수 없습니다.", "Move items to mouse", 0)
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
