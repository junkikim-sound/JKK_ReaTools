--========================================================
-- @title JKK_UndoLabels
-- @author Junki Kim
-- @noindex
--========================================================

local LABEL_PREFIX = "JKK_"

local LABELS = {

    -- Project Memo
    ["memo.save_project_note"] = "JKK_Edit Project Memo",  -- 메모 입력 포커스 해제 시 변경 내용을 프로젝트에 기록

    -- Color Palette
    ["color_palette.apply_color_palette"] = "JKK_Apply Color Palette",  -- 선택한 트랙 또는 아이템에 팔레트 색상을 적용

    -- Item Tools (NEW)
    ["item.batch_take_volume_applied"] = "JKK_Batch Take Volume Applied",  -- 선택 아이템의 활성 Take 볼륨 일괄 변경
    ["item.batch_pan_applied"] = "JKK_Batch Pan Applied",  -- 선택 아이템의 Take 패닝 일괄 변경
    ["item.batch_pitch_applied"] = "JKK_Batch Pitch Applied",  -- 선택 아이템의 Take 피치를 일괄 조정
    ["item.batch_playback_rate_applied"] = "JKK_Batch Playback Rate Applied",  -- 선택 아이템의 재생 속도를 일괄 조정
    ["item.group_time_stretch_applied"] = "JKK_Group Time Stretch Applied",  -- 선택 아이템 그룹의 시간 길이를 비율로 늘리거나 줄임
    ["item.reset_volume"] = "JKK_Reset Volume",  -- 선택 아이템의 Take 볼륨 초기화
    ["item.reset_pan"] = "JKK_Reset Pan",  -- 선택 아이템의 Take 패닝 중앙 초기화
    ["item.reset_pitch"] = "JKK_Reset Pitch",  -- 선택 아이템의 Take 피치 초기화
    ["item.reset_playback_rate"] = "JKK_Reset Playback Rate",  -- 선택 아이템의 재생 속도 1.0으로 초기화
    ["item.reset_group_stretch"] = "JKK_Reset Group Stretch",  -- 그룹 스트레치 비율과 적용 상태 초기화
    ["item.bounce_in_place"] = "JKK_Bounce in place.",  -- 선택 아이템을 현재 위치에 렌더링해 교체/정리
    ["item.take_reverse"] = "JKK_Take Reverse",  -- 선택 아이템의 활성 Take를 역재생으로 전환
    ["item.next_take"] = "JKK_Next Take",  -- 선택 아이템의 다음 Take 활성화
    ["item.prev_take"] = "JKK_Prev Take",  -- 선택 아이템의 이전 Take 활성화
    ["item.render_to_new_take"] = "JKK_Render to New Take",  -- 선택 아이템을 렌더링해 새 Take 생성
    ["item.set_item_property"] = "JKK_Set Item %s",  -- 선택 아이템의 속성(%s)을 설정하는 작업명 템플릿
    ["item.set_take_channel_mode"] = "JKK_Set Take Channel Mode",  -- 선택 아이템의 Take 채널 모드 변경
    ["item.set_take_pitch_mode"] = "JKK_Set Take Pitch Mode",  -- 선택 아이템의 Take 피치 처리 모드 변경
    ["item.update_interval_width"] = "JKK_Update Interval Width",  -- 아이템 간격(Arrange Width) 재배치
    ["item.shuffle_item_order"] = "JKK_Shuffle Item Order",  -- 선택 아이템들의 순서를 섞어 재배치
    ["item.delete_all_take_markers"] = "JKK_Delete All Take Markers from Selected Items",  -- 선택 아이템 모든 Take의 마커 삭제
    ["item.live_grid_split"] = "JKK_Live Grid Split Items",  -- 그리드 분할 실시간 적용
    ["item.undo_live_grid_split"] = "JKK_Undo Live Grid Split",  -- 실시간 그리드 분할을 취소하거나 복구
    ["item.grid_split_items"] = "JKK_Grid Split Items",  -- 선택 아이템을 그리드 기준으로 분할
    ["item.split"] = "JKK_Split",  -- 선택 아이템을 지정 지점에서 분할
    ["item.split_takes"] = "JKK_Split & Takes",  -- 분할 후 Take 관련 처리를 함께 실행

    -- Loopmaker / Sequencer
    ["loopmaker.create_loop"] = "JKK_Create Loopmaker",  -- 설정한 구간으로 루프 아이템을 확정 생성
    ["loopmaker.create_sequence"] = "JKK_Create Sequencer Arrangement",  -- Sequencer 설정으로 아이템 시퀀스 생성
    ["loopmaker.glue_incomplete"] = "JKK_Loopmaker: Incomplete Glue (originals preserved)",  -- Glue가 실패했을 때 원본을 보존했다는 오류/복구 기록

    -- Renamer
    ["renamer.batch_rename"] = "JKK_Smart Batch Rename",  -- Renamer에서 선택 항목 이름 일괄 변경
    ["renamer.find_replace"] = "JKK_Find & Replace",  -- Renamer에서 찾기 및 바꾸기를 적용 (1.1.x, 현재 미사용)
    ["renamer.queue_apply"] = "JKK_Rename Queue",  -- Renamer Queue 탭의 모든 활성 단계를 한 번에 적용

    -- Renamer Lite
    ["renamer_lite.create_regions_from_items"] = "JKK_Create Regions from Items",  -- Renamer Lite에서 선택 아이템으로 리전 생성
    ["renamer_lite.jkk_reatools_rename"] = "JKK_Rename",  -- Renamer Lite에서 선택 항목 이름 변경

    -- Renderer
    ["renderer.set_region_matrix_from_time_selection"] = "JKK_Set Region Render Matrix from Time Selection",  -- 타임 셀렉션과 겹치는 리전을 렌더 매트릭스에 설정

    -- Take Marker
    ["take_marker.create_peak_markers"] = "JKK_Peak Markers from Split Dyn Keep Regions",  -- Split Dyn 유지 구간마다 Peak Take Marker 생성

    -- Track Tools (NEW)
    ["track.delete_selected_regions"] = "JKK_Delete Selected Regions",  -- 선택된 리전 삭제
    ["track.delete_unused"] = "JKK_Delete Unused Tracks",  -- 사용하지 않는 트랙 삭제
    ["track.reset_pan"] = "JKK_Reset Pan",  -- 선택 트랙 패닝 초기화
    ["track.reset_volume"] = "JKK_Reset Volume",  -- 선택 트랙 볼륨 초기화
    ["track.reset_width"] = "JKK_Reset Width",  -- 선택 트랙 스테레오 폭 초기화
    ["track.round_all_tracks_volume_to_0_5db"] = "JKK_Round All Tracks Volume to 0.5dB",  -- 모든 트랙의 볼륨을 0.5dB 단위로 반올림
    ["track.round_selected_tracks_volume_to_0_5db"] = "JKK_Round Selected Tracks Volume to 0.5dB",  -- 선택 트랙의 볼륨을 0.5dB 단위로 반올림
    ["track.set_master_parent_output_channels"] = "JKK_Set Track Master/Parent Output Channels",  -- 트랙의 마스터/부모 출력 채널 위치 설정
    ["track.set_selected_tracks_automation_mode"] = "JKK_Set Selected Tracks Automation Mode",  -- 선택 트랙의 자동화 모드 변경
    ["track.set_selected_tracks_panning"] = "JKK_Set Selected Tracks Panning",  -- 선택 트랙의 패닝값 변경
    ["track.set_selected_tracks_volume"] = "JKK_Set Selected Tracks Volume",  -- 선택 트랙의 볼륨값 변경
    ["track.set_selected_tracks_width"] = "JKK_Set Selected Tracks Width",  -- 선택 트랙의 스테레오 폭 변경
    ["track.set_track_channels"] = "JKK_Set Track Channels",  -- 선택 트랙의 채널 수 변경

    -- Track Manager
    ["track_manager.activate_selected_tracks"] = "JKK_Activate Selected Tracks",  -- 선택 트랙을 Active 상태로 전환
    ["track_manager.deactivate_selected_tracks"] = "JKK_Deactivate Selected Tracks",  -- 선택 트랙을 Inactive 상태로 전환
    ["track_manager.jkk_sort_sibling_tracks_a_z"] = "JKK_Sort Sibling Tracks A-Z",  -- 같은 폴더 레벨의 트랙 이름을 A-Z로 정렬
    ["track_manager.modify_property"] = "JKK_Modify Track Property",  -- Track Manager에서 트랙 속성 변경
    ["track_manager.rename_track"] = "JKK_Rename Track",  -- Track Manager에서 트랙 이름 변경
    ["track_manager.toggle_active"] = "JKK_Toggle Track Active",  -- Track Manager에서 단일 트랙 활성 상태 토글
    ["track_manager.toggle_selected"] = "JKK_Toggle Selected Tracks Active",  -- 선택한 여러 트랙의 활성 상태 토글

    -- Search
    ["search.insert_fx"] = "JKK_Search Insert FX: %s",  -- 검색 결과 FX를 선택된 트랙/아이템에 삽입
    ["search.insert_fx_chain"] = "JKK_Search Insert FX Chain: %s",  -- 검색 결과 FX Chain을 선택된 트랙/아이템에 삽입
    ["search.insert_instrument_track"] = "JKK_Search Insert Instrument Track: %s",  -- 가상악기를 새 트랙에 삽입
    ["search.insert_fx_multi"] = "JKK_Search Insert %s FX",  -- 여러 FX를 한 번에 선택된/드롭한 대상에 삽입

    -- Folder Items
    ["folder_items.create"] = "JKK_Create/Update Folder Items",  -- 선택 폴더 트랙의 폴더 아이템 생성/갱신(+접힌 폴더 그룹 재계산)
    ["folder_items.collapse"] = "JKK_Collapse Folder (Folder Items)",  -- 폴더 접기 + 폴더 아이템별 그룹핑
    ["folder_items.expand"] = "JKK_Expand Folder (Folder Items)",  -- 폴더 펼치기 + 그룹 해제/하위 접힌 폴더 그룹 복구
    ["folder_items.group_tracks"] = "JKK_Group Selected Tracks into Folder",  -- 선택 트랙들을 새 상위(폴더) 트랙으로 묶기

    -- Variator
    ["variator.apply"] = "JKK_Create Variations",  -- Variator 미리보기 결과를 복제 아이템으로 확정 (Keep Original OFF면 원본 제거 포함)
    ["variator.apply_failed"] = "JKK_Variator: Apply Failed (No Changes Kept)",  -- 확정 중 오류: 생성분을 지운 뒤 닫힌 Undo 블록
    ["variator.cleanup_leftovers"] = "JKK_Variator: Clean Up Leftover Preview Items",  -- 비정상 종료로 남은 이전 세션 임시 아이템 삭제
}
local M = {}

function M.Label(key, ...)
    local template = LABELS[key]
    if template == nil then
        error("JKK_UndoLabels: undefined Undo label key: " .. tostring(key), 2)
    end
    if select("#", ...) > 0 then
        template = string.format(template, ...)
    end
    if template:sub(1, #LABEL_PREFIX) == LABEL_PREFIX then
        return template
    end
    return LABEL_PREFIX .. template
end

return M
