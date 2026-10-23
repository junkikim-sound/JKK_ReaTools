--========================================================
-- @title JKK_Volume Rounder
-- @author Junki Kim
-- @version 1.0.0
--========================================================

-- 선택된 트랙의 볼륨을 0.5dB 단위로 반올림
function round_to_half_db(vol_val)
    if vol_val <= 0 then return 0 end
    -- Linear 볼륨을 dB로 변환
    local db = 20 * math.log(vol_val, 10)
    -- 0.5 단위로 반올림
    local rounded_db = math.floor(db * 2 + 0.5) / 2
    -- 다시 Linear 볼륨으로 변환
    return 10^(rounded_db / 20)
end

function main()
    reaper.Undo_BeginBlock()
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        local current_vol = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
        local new_vol = round_to_half_db(current_vol)
        
        -- 값이 다를 때만 적용
        if math.abs(current_vol - new_vol) > 0.0001 then
            reaper.SetMediaTrackInfo_Value(track, "D_VOL", new_vol)
        end
    end
    reaper.Undo_EndBlock("Round Volume to 0.5dB", -1)
end

main()