-- @description JKK_Meter
-- @author Junki Kim
options = reaper.gmem_attach('JKK_Meter_Mem') 

local win_w, win_h = 800, 150
gfx.init("JKK Minimeter", win_w, win_h, 513)

-- --- 사용자 설정 범위 ---
local g_gain_min, g_gain_max            = 0.1,  1.5
local s_zoom_min, s_zoom_max            = 0.1,  2.3
local spec_ceil_min, spec_ceil_max      = 100,  -20
local spec_floor_min, spec_floor_max    = -144, -20
local spec_offset = 55

-- 레이아웃 (Gonio | Scope | Spec)
local slider3 = 0.15 -- Gonio 끝
local slider4 = 0.30 -- Scope 끝

-- 데이터 버퍼 정보
local buf_len = 100000
local fft_size = 4096
local fft_bins = 2048

-- UI의 설정
    -- 전체 설정
    gfx.setfont(1, "Arial", 12) -- 폰트
    local bg_r, bg_g, bg_b, bg_a                = 025/255, 025/255, 025/255, 1.0 -- 배경
    local line_r, line_g, line_b, line_a        = 200/255, 200/255, 200/255, 0.3 -- 흰색 선

    -- Color 1: -inf에 가까울 때
    -- Color 2: 중간 크기일 때
    -- Color 3: 0dB에 가까울 때
    local midpoint = 0.5
    local steepness = 1.2 -- 피크에 가까워질수록 색이 변하는 정도의 급하기

    -- Gonio Color
    local dot1_r, dot1_g, dot1_b, dot1_a        = 006/255, 143/255, 195/255, 0.1
    local dot2_r, dot2_g, dot2_b, dot2_a        = 006/255, 143/255, 195/255, 0.8
    local dot3_r, dot3_g, dot3_b, dot3_a        = 227/255, 219/255, 142/255, 1.0
    local gr_peak, gg_peak, gb_peak             = 255/255, 000/255, 000/255      -- Peak 컬러
        local gonio_peak_hold_time = 2.0  -- 피크 유지 시간 (초)
        local gonio_max_peak_dots = 100   -- 한 화면에 표시할 최대 피크 점 개수
        local gonio_peaks = {} -- 피크 좌표를 저장할 테이블

    -- Scope Color
    local scp1_r, scp1_g, scp1_b, scp1_a        = 006/255, 143/255, 195/255, 0.1
    local scp2_r, scp2_g, scp2_b, scp2_a        = 006/255, 143/255, 195/255, 0.8
    local scp3_r, scp3_g, scp3_b, scp3_a        = 227/255, 219/255, 142/255, 1.0
    local scope_speed = 0.1 -- 스코프 속도

    -- Spectrum Color
    local sptr1_r, sptr1_g, sptr1_b, sptr1_a    = 006/255, 143/255, 195/255, 0.1
    local sptr2_r, sptr2_g, sptr2_b, sptr2_a    = 006/255, 143/255, 195/255, 0.8
    local sptr3_r, sptr3_g, sptr3_b, sptr3_a    = 227/255, 219/255, 142/255, 1.0
    local peak_r, peak_g, peak_b, peak_a        = 195/255, 195/255, 195/255, 1.0 -- Peak 유지 라인 컬러

        local area_decay_rate = 5.0 -- 값이 작을수록 더 천천히 떨어짐 (부드러움)
        local peak_hold_time = 0.5  -- 피크 유지 시간 (초)
        local peak_decay_rate = 10.0 -- 떨어지는 속도 (dB/frame approx)
        -- [Data Storage] 피크 데이터를 저장할 테이블 (초기화)
        local spec_smooth_vals = {}
        local spec_peaks = {} 
        local spec_peak_times = {}
        -- 테이블 초기화 (최초 1회)
        for i = 1, 4096 do 
            spec_smooth_vals[i] = -144
            spec_peaks[i] = -144 
            spec_peak_times[i] = 0
        end

-- [그리기 함수들]
function draw_gonio(x, y, w, h, gain)
    local cx, cy = x + w * 0.5, y + h * 0.5
    local dim_limit = math.min(w, h)
    local guide_size = dim_limit * 0.4 
    local dot_size = dim_limit * 0.40 * gain 
    local now = reaper.time_precise()
    
    local true_zero_limit = 1.0 
    local visual_limit = guide_size / (2 * dot_size)

    -- 가이드 라인 그리기
    gfx.set(line_r, line_g, line_b, line_a)
    gfx.line(cx - guide_size, cy - guide_size, cx + guide_size, cy + guide_size)
    gfx.line(cx + guide_size, cy - guide_size, cx - guide_size, cy + guide_size)
    
    local write_idx = reaper.gmem_read(0)
    
    -- 일반 점들 그리기 루프
    for i = 0, 2000, 2 do
        local idx = (write_idx - i - 1) % buf_len
        local l, r = reaper.gmem_read(10000 + idx), reaper.gmem_read(110000 + idx)
        
        local peak_intensity = math.max(math.abs(l), math.abs(r))
        local is_clipping = peak_intensity >= true_zero_limit
        
        -- 1. [핵심] 0dB 초과 시 피크 좌표 저장
        if peak_intensity >= true_zero_limit and #gonio_peaks < gonio_max_peak_dots then
            local cl, cr = math.max(-visual_limit, math.min(visual_limit, l)), math.max(-visual_limit, math.min(visual_limit, r))
            local px, py = cx + (cl - cr) * dot_size, cy - (cl + cr) * dot_size
            table.insert(gonio_peaks, {px = px, py = py, time = now})
        end

        -- 일반 점 색상 보간 (피크에 가까울수록 빨라짐)
        local t = math.min(1.0, peak_intensity / visual_limit)
        local gonio_r, gonio_g, gonio_b, gonio_a

        if t < midpoint then
            local local_t = t / midpoint 
            local curve = local_t ^ steepness
            
            gonio_r = dot1_r + (dot2_r - dot1_r) * curve
            gonio_g = dot1_g + (dot2_g - dot1_g) * curve
            gonio_b = dot1_b + (dot2_b - dot1_b) * curve
            gonio_a = dot1_a + (dot2_a - dot1_a) * curve
        else
            local local_t = (t - midpoint) / (1 - midpoint)
            local curve = local_t ^ steepness
            
            gonio_r = dot2_r + (dot3_r - dot2_r) * curve
            gonio_g = dot2_g + (dot3_g - dot2_g) * curve
            gonio_b = dot2_b + (dot3_b - dot2_b) * curve
            gonio_a = dot2_a + (dot3_a - dot2_a) * curve
        end

        local cl, cr = math.max(-visual_limit, math.min(visual_limit, l)), math.max(-visual_limit, math.min(visual_limit, r))
        local px, py = cx + (cl - cr) * dot_size, cy - (cl + cr) * dot_size

        gfx.set(gonio_r, gonio_g, gonio_b, (1 - (i / 2000)))
        gfx.x, gfx.y = px, py
        gfx.setpixel(gonio_r, gonio_g, gonio_b)
    end
    
    -- 2. [피크 유지] 저장된 피크 점들을 2초 동안 별도 색상으로 표시
    for i = #gonio_peaks, 1, -1 do
        local p = gonio_peaks[i]
        if (now - p.time) > gonio_peak_hold_time then
            table.remove(gonio_peaks, i)
        else
            gfx.set(gr_peak, gg_peak, gb_peak, 1.0)
            gfx.rect(p.px - 1, p.py - 1, 2, 2) 
        end
    end
    
    gfx.set(1, 1, 1, 0.5)
    gfx.x, gfx.y = x + 5, y + 5
    gfx.drawstr("Gonio")
end

function draw_scope(x, y, w, h, zoom)
    local cy = y + h * 0.5
    local write_idx = reaper.gmem_read(0)
    
    -- step: 1픽셀당 표현해야 할 데이터의 양 (예: 125 샘플)
    local step = (buf_len / w) * scope_speed 
    local scan_stride = math.max(1, math.floor(step / 8)) 

    for m = 0, w - 1 do
        -- 현재 픽셀(m)이 보여줘야 할 데이터의 시작 위치 계산
        local start_pos = (write_idx - (w - m) * step)
        
        -- [Min-Max 탐색]
        -- 해당 구간(step) 안에서 가장 높은 값(max_v)과 낮은 값(min_v)을 찾습니다.
        local max_v = -100 -- 초기값
        local min_v = 100  -- 초기값
        local abs_peak = 0 -- 색상 결정을 위한 절대값 피크
        
        for s = 0, step - 1, scan_stride do
            local read_ptr = math.floor(start_pos + s) % buf_len
            local raw_val = reaper.gmem_read(10000 + read_ptr) -- Left Channel
            
            if raw_val > max_v then max_v = raw_val end
            if raw_val < min_v then min_v = raw_val end
            
            local abs_v = math.abs(raw_val)
            if abs_v > abs_peak then abs_peak = abs_v end
        end
        
        -- 값 보정 (Zoom 적용)
        local draw_max = max_v * zoom * 0.5
        local draw_min = min_v * zoom * 0.5
        
        -- 좌표 변환 (화면 위아래 뒤집힘 주의: -를 붙여야 함)
        local y_top = cy - (draw_max * h)
        local y_bottom = cy - (draw_min * h)
        
        -- 화면 밖으로 나가는 것 방지 (Clamping)
        y_top = math.max(y, math.min(y + h, y_top))
        y_bottom = math.max(y, math.min(y + h, y_bottom))
        
        -- [색상 계산] 구간 내 최대 피크(abs_peak)를 기준으로 색상 결정
        local t = math.min(1.0, abs_peak * zoom)
        local local_t = t ^ steepness
        local scp_r, scp_g, scp_b, scp_a

        if t < midpoint then
            local local_t = t / midpoint
            local curve = local_t ^ steepness

            scp_r = scp1_r + (scp2_r - scp1_r) * curve
            scp_g = scp1_g + (scp2_g - scp1_g) * curve
            scp_b = scp1_b + (scp2_b - scp1_b) * curve
            scp_a = scp1_a + (scp2_a - scp1_a) * curve
        else
            local local_t = (t - midpoint) / (1 - midpoint)
            local curve = local_t ^ steepness
            
            scp_r = scp2_r + (scp3_r - scp2_r) * curve
            scp_g = scp2_g + (scp3_g - scp2_g) * curve
            scp_b = scp2_b + (scp3_b - scp2_b) * curve
            scp_a = scp2_a + (scp3_a - scp2_a) * curve
        end
        
        gfx.set(scp_r, scp_g, scp_b, scp_a)

        -- [그리기] 점을 잇는 게 아니라, 수직선(Bar)을 그립니다.
        -- 만약 파형이 거의 없어서 위아래 차이가 1픽셀 미만이면 점을 찍습니다.
        if math.abs(y_bottom - y_top) < 1 then
            gfx.rect(x + m, y_top, 1, 1)
        else
            -- 윗점에서 아랫점까지 선 긋기
            gfx.line(x + m, y_top, x + m, y_bottom)
        end
    end
    
    gfx.set(1, 1, 1, 0.5)
    gfx.x, gfx.y = x + 5, y + 5
    gfx.drawstr("Scope")
end

function draw_spectrum(x, y, w, h, ceil, floor)
    local range = ceil - floor
    local srate = reaper.gmem_read(1)
    if srate == 0 then srate = 48000 end
    local now = reaper.time_precise()
    
    -- 1. Grid
    gfx.set(line_r, line_g, line_b, line_a)
    local k_max_log = math.log(fft_bins)
    
    -- Hz Lines
    local freqs = {100, 1000, 10000}
    local labels = {"100", "1k", "10k"}
    for i, freq in ipairs(freqs) do
        local k = freq * fft_size / srate
        if k > 0 then
            local x_norm = math.log(k) / k_max_log
            if x_norm > 0 and x_norm < 1 then
                local gx = x + x_norm * w
                gfx.line(gx, y, gx, y + h)
                gfx.x, gfx.y = gx + 2, y + h - 12
                gfx.drawstr(labels[i])
            end
        end
    end
    
    -- 2. Draw Spectrum (Fill & Peak Line)
    local ox, oy = x, y + h       -- Fill용 이전 좌표
    local pox, poy = x, y + h     -- Peak Line용 이전 좌표
    local k = 1
    
    while k < fft_bins do
        local k_int = math.floor(k)
        local mag = reaper.gmem_read(300000 + k_int)
        local db = 20 * math.log(mag + 0.0000001, 10) - spec_offset
        local raw_db = 20 * math.log(mag + 0.0000001, 10) - spec_offset

        -- [Area Smoothing Logic] 면 프리즈 효과
        local smooth_db = spec_smooth_vals[k_int] or -144
        if raw_db >= smooth_db then
            smooth_db = raw_db -- 올라갈 땐 즉시 (Attack)
        else
            smooth_db = smooth_db - area_decay_rate -- 내려갈 땐 천천히 (Decay)
        end
        spec_smooth_vals[k_int] = smooth_db

        -- [Peak Hold Logic]
        local current_peak = spec_peaks[k_int] or -144
        local last_time = spec_peak_times[k_int] or 0
        
        if db >= current_peak then
            spec_peaks[k_int] = db
            spec_peak_times[k_int] = now
        else
            if (now - last_time) > peak_hold_time then
                spec_peaks[k_int] = current_peak - peak_decay_rate
            else
            end
        end
        local peak_db = spec_peaks[k_int]

        -- --- 좌표 계산 ---
        -- 1) Real-time Fill (면)
        local t = math.max(0, math.min(1, (smooth_db - floor) / range))
        local t_curve = t ^ steepness
        local sptr_r, sptr_g, sptr_b, sptr_a
        local dy = y + h - (t * h)
        
        -- 2) Peak Line (선)
        local pt = (peak_db - floor) / range
        pt = math.max(0, math.min(1, pt))
        local pdy = y + h - (pt * h)

        -- X 좌표 (공통)
        local x_norm = math.log(k) / k_max_log
        local dx = x + (x_norm * w)
        
        -- --- 그리기 (Draw) ---
        -- A. Filled Area (Gradient)
        if t < midpoint then
            -- [구간 A -> B] (0.0 ~ 0.5 사이)
            -- 0~0.5 범위를 0~1로 확장하여 비율(ratio) 계산
            local local_t = t / midpoint 
            local curve = local_t ^ steepness
            sptr_r = sptr1_r + (sptr2_r - sptr1_r) * curve
            sptr_g = sptr1_g + (sptr2_g - sptr1_g) * curve
            sptr_b = sptr1_b + (sptr2_b - sptr1_b) * curve
            sptr_a = sptr1_a + (sptr2_a - sptr1_a) * curve
        else
            local local_t = (t - midpoint) / (1 - midpoint)
            local curve = local_t ^ steepness
            
            sptr_r = sptr2_r + (sptr3_r - sptr2_r) * curve
            sptr_g = sptr2_g + (sptr3_g - sptr2_g) * curve
            sptr_b = sptr2_b + (sptr3_b - sptr2_b) * curve
            sptr_a = sptr2_a + (sptr3_a - sptr2_a) * curve
        end
        
        gfx.set(sptr_r, sptr_g, sptr_b, sptr_a)
        if k > 1 then
            gfx.triangle(ox, y + h, ox, oy, dx, dy, dx, y + h)
        end
        
        -- B. Peak Hold Line
        -- 피크 라인은 항상 맨 위에 그려지도록 루프 마지막에 그리거나, 
        -- 여기서는 순서대로 그리되 색상을 밝게 하여 눈에 띄게 함.
        -- (gfx.line은 triangle 위에 그려짐)
        gfx.set(peak_r, peak_g, peak_b, peak_a)
        if k > 1 then
            gfx.line(pox, poy, dx, pdy)
        end
        
        -- 좌표 갱신
        ox, oy = dx, dy
        pox, poy = dx, pdy
        
        -- Step 증가
        local step = 1
        if k > 50 then step = k * 0.05 end
        k = k + step
    end
    
    gfx.set(1, 1, 1, 0.5)
    gfx.x, gfx.y = x + 5, y + 5
    gfx.drawstr("Spectrum")
end

function run()
    if gfx.getchar() == 27 then return end 

    -- 맥 도킹 우클릭 메뉴 지원
    if gfx.mouse_cap == 2 then -- 우클릭
        gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
        local is_docked = gfx.dock(-1) > 0
        local selection = gfx.showmenu((is_docked and "!" or "") .. "Dock to Docker")
        
        if selection == 1 then
            if is_docked then
                gfx.dock(0) -- 이미 도킹되어 있다면 해제 (Floating)
            else
                -- 513: 상단 도커(Top Docker)에 바로 붙이는 특수 번호
                -- 만약 이 번호가 안 먹히면 1을 시도해 보세요.
                gfx.dock(513) 
            end
        end
    end

    -- 백엔드 슬라이더 값 읽기
    local s1 = reaper.gmem_read(2)
    local s2 = reaper.gmem_read(3)

    local gain = g_gain_min + (g_gain_max - g_gain_min) * s1
    local ceil = spec_ceil_min + (spec_ceil_max - spec_ceil_min) * s1
    local zoom = s_zoom_min + (s_zoom_max - s_zoom_min) * s1
    local floor = spec_floor_min + (spec_floor_max - spec_floor_min) * s2

    gfx.set(bg_r, bg_g, bg_b, bg_a)
    gfx.rect(0, 0, gfx.w, gfx.h)
    
    local d1, d2 = math.floor(gfx.w * slider3), math.floor(gfx.w * slider4)
    gfx.set(0.3, 0.3, 0.3, 1)
    gfx.line(d1, 0, d1, gfx.h)
    gfx.line(d2, 0, d2, gfx.h)
    
    draw_gonio(0, 0, d1, gfx.h, gain)
    draw_scope(d1, 0, d2 - d1, gfx.h, zoom)
    draw_spectrum(d2, 0, gfx.w - d2, gfx.h, ceil, floor)
    
    gfx.update()
    reaper.defer(run)
end

run()