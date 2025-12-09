-- Render Selected Items to One Stereo File
-- by Jungi Kim

function main()
    local cnt = reaper.CountSelectedMediaItems(0)
    if cnt == 0 then return end

    reaper.Undo_BeginBlock()

    -- 타임셀렉션을 선택된 아이템 전체 범위로 설정
    local min_pos = math.huge
    local max_end = -math.huge

    for i = 0, cnt - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local ed   = pos + len

        if pos < min_pos then min_pos = pos end
        if ed  > max_end then max_end = ed end
    end

    reaper.GetSet_LoopTimeRange(true, false, min_pos, max_end, false)

    -- Render settings 임시 변경: Selected media items → Time selection
    -- 실제로는 time selection 기반으로 render를 수행하도록 강제
    local render_cfg = reaper.GetSetProjectInfo_String(0, "RENDER_SETTINGS", "", false)
    -- 1 = time selection only
    reaper.GetSetProjectInfo_String(0, "RENDER_SETTINGS", "1", true)

    -- Render 실행 (파일명 자동 생성)
    reaper.Main_OnCommand(42329, 0) -- File: Render project, using the most recent render settings

    -- 설정 원복
    reaper.GetSetProjectInfo_String(0, "RENDER_SETTINGS", render_cfg, true)

    reaper.Undo_EndBlock("Render selected items to one stereo file", -1)
end

main()
