-- Move Items to Mouse Location (using native "move cursor to mouse" action)
-- by Jungi Kim

function main()
    local cnt = reaper.CountSelectedMediaItems(0)
    if cnt == 0 then return end

    -- 현재 편집 커서 위치 저장
    local old_cursor = reaper.GetCursorPosition()

    -- *** 핵심 ***
    -- native action: Move edit cursor to mouse cursor
    -- 이 기능은 어떤 환경에서도 정확히 마우스 위치를 잡음
    reaper.Main_OnCommand(40514, 0)  -- Move edit cursor to mouse cursor

    -- 마우스 위치 = 편집 커서 위치
    local mouse_pos = reaper.GetCursorPosition()

    -- 편집 커서 원래 위치 복귀 준비는 나중에 할 것
    --------------------------------------------------

    -- 선택된 아이템들의 시작 위치 분석
    local items = {}
    local min_start = math.huge

    for i = 0, cnt - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        items[#items+1] = {item=item, pos=pos}
        if pos < min_start then min_start = pos end
    end

    local offset = mouse_pos - min_start

    -- 이동 후 음수 방지
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
        reaper.SetMediaItemInfo_Value(items[i].item, "D_POSITION", items[i].pos + offset)
    end

    reaper.PreventUIRefresh(0)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Move items to mouse location (stable version)", -1)

    -- 편집 커서 원위치 복구
    reaper.SetEditCurPos(old_cursor, false, false)
end

main()
