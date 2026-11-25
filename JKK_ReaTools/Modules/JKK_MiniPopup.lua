--========================================================
-- @title JKK_MiniPopup
-- @author Junki Kim
-- @noindex
--========================================================
-- 입력창 바로 아래에 뜨는 "미니 팝업"(자동완성/제안 목록) 공용 그리기 모듈.
-- JKK_Search가 접힌 상태에서 보여주는 결과 팝업과 같은 모양:
--   * 테두리 1px, 둥근 모서리 없음, 목록 배경(list_bg)
--   * 행 높이 = 글자 높이 x 2, 선택 행 = 배경 + 왼쪽 강조 세로줄, 마우스 오버 = 옅은 배경
--   * [배지] 이름(검색어 강조) 보조텍스트 ............ 오른쪽 설명(흐린 색)
--   * 포커스를 빼앗지 않는 별도 창 (NoFocusOnAppearing / NoNav)
--
-- 같은 파일이 두 곳에 있다. 수정할 때는 둘 다 똑같이 바꿀 것:
--   JKK_ReaTools/Modules/JKK_MiniPopup.lua
--   JKK_MediaBrowser/ui/components/mini_popup.lua
--
-- 사용법:
--   local MiniPopup = dofile(".../JKK_MiniPopup.lua")
--   local P = MiniPopup.Palette(base_bg, control_bg, text_main, accent_main)
--   local st = {}                       -- 팝업마다 하나씩, 계속 재사용 (스크롤/배지 폭 캐시)
--   local res = MiniPopup.Draw(ctx, st, {
--       id = "Suggestions##my_popup", x = ix, y = iy_bottom, w = iw, palette = P,
--       count = #items, row = function(i) return { name = ..., badge = ..., sub = ..., detail = ... } end,
--       selected = sel, ensure_visible = moved, highlight = "term", key = "kind\1query",
--       footer = function(ctx, P) ... end,  -- (선택) 목록 아래 고정 영역
--   })
--   res.clicked  : 클릭한 행 번호 (없으면 nil)
--   res.focused  : 팝업 창이 포커스를 가졌는지
--   res.hovered  : 마우스가 팝업 위에 있는지
--   res.rect     : {x, y, w, h} 팝업 창의 화면 좌표 (바깥 클릭 판정용)
--
-- 열 모드 (UCS, 와일드카드처럼 항목이 여러 열로 나뉘는 목록):
--   columns = { {samples = 전체목록의_열1_글자들}, {samples = ..., color = "muted"} },
--   right_from = 2,                     -- (선택) 2번째 열부터 오른쪽 끝에 모으기
--   row = function(i) return { cols = {"AIRBlow", "AIR", "BLOW"}, tooltip = "설명...", detail = "..." } end
--========================================================

local M = {}

----------------------------------------------------------
-- 색상 (ImGui 없이 순수 Lua로 계산: 어디서 불러도 안전)
----------------------------------------------------------
local function Ch(c)
    c = math.floor(tonumber(c) or 0)
    return (c >> 24) & 255, (c >> 16) & 255, (c >> 8) & 255, c & 255
end

local function Pack(r, g, b, a)
    local function B(v) return math.max(0, math.min(255, math.floor(v + 0.5))) end
    return (B(r) << 24) | (B(g) << 16) | (B(b) << 8) | B(a)
end

local function Blend(c1, c2, t, alpha)
    local r1, g1, b1, a1 = Ch(c1)
    local r2, g2, b2, a2 = Ch(c2)
    return Pack(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t, alpha or (a1 + (a2 - a1) * t))
end
M.Blend = Blend

local function IsDark(c)
    local r, g, b = Ch(c)
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255 < 0.5
end

-- JKK_Search의 BuildPalette와 같은 계산식
function M.Palette(base, ctrl, text, accent)
    base   = tonumber(base) or 0x1E1E22FF
    text   = tonumber(text) or 0xEDEDEDFF
    ctrl   = tonumber(ctrl) or Blend(base, text, 0.12, 255)
    accent = tonumber(accent) or 0x4FA3E0FF
    local dark = IsDark(base)
    return {
        base       = base,
        text       = text,
        accent     = accent,
        muted      = Blend(text, base, 0.42),
        faint      = Blend(text, base, 0.62),
        list_bg    = Blend(base, 0x000000FF, dark and 0.18 or 0.05, 255),
        row_hover  = Blend(base, ctrl, 0.55, 255),
        row_sel    = Blend(base, ctrl, 0.95, 255),
        row_border = Blend(base, ctrl, 0.45, 255),
        header_bg  = Blend(base, ctrl, 0.25, 255),
        badge_line = Blend(text, base, 0.60),
        badge_text = Blend(text, base, 0.28),
        hl         = accent,
    }
end

----------------------------------------------------------
-- 작은 유틸
----------------------------------------------------------
local function Fn(name)
    local f = reaper[name]
    return type(f) == "function" and f or nil
end

local function Flag(name)
    local f = Fn("ImGui_" .. name)
    if not f then return 0 end
    local ok, v = pcall(f)
    return (ok and type(v) == "number") and v or 0
end

-- 자식 창 안전 처리 (JKK_MediaBrowser의 ChildWindowGuard와 같은 방식):
-- ReaImGui에서는 BeginChild를 호출해도 상황에 따라 자식 창이 실제로 열리지 않는 경우가 있다
-- (예: 자동 크기 창의 첫 프레임). 그때 EndChild를 부르면
-- "EndChild: Assertion failed: child_window->Flags & ChildWindow" 오류가 난다.
-- 현재 창의 위치/크기로 자식 창에 실제로 들어갔는지 확인하고, 들어간 경우에만 EndChild 한다.
local function WindowKey(ctx)
    local R = reaper
    local x, y = R.ImGui_GetWindowPos(ctx)
    local w, h = R.ImGui_GetWindowSize(ctx)
    if type(x) ~= "number" or type(w) ~= "number" then return nil end
    return string.format("%.3f:%.3f:%.3f:%.3f", x, y, w, h)
end
local function BeginChildSafe(ctx, id, w, h, child_flags, window_flags)
    local before = WindowKey(ctx)
    local visible = reaper.ImGui_BeginChild(ctx, id, w, h, child_flags or 0, window_flags or 0)
    local after = WindowKey(ctx)
    -- 위치/크기를 읽을 수 없으면 일반적인 Begin/End 짝을 그대로 따른다
    local entered = (before == nil or after == nil) or (before ~= after)
    return visible and entered, entered
end
M.BeginChildSafe = BeginChildSafe

local function TextW(ctx, s)
    return (reaper.ImGui_CalcTextSize(ctx, s))
end

-- UTF-8 안전 말줄임
local function FitText(ctx, text, max_w)
    text = tostring(text or "")
    if max_w <= 0 or text == "" then return "" end
    if TextW(ctx, text) <= max_w then return text end
    local ell = "..."
    if TextW(ctx, ell) > max_w then return "" end
    local ok, n = pcall(utf8.len, text)
    if not ok or not n then
        local c = text
        while #c > 0 do
            c = c:sub(1, -2)
            if TextW(ctx, c .. ell) <= max_w then return c .. ell end
        end
        return ell
    end
    local lo, hi, best = 0, n - 1, ell
    while lo <= hi do
        local mid = (lo + hi) // 2
        local byte_end = (mid == 0) and 0 or ((utf8.offset(text, mid + 1) or (#text + 1)) - 1)
        local cand = text:sub(1, byte_end) .. ell
        if TextW(ctx, cand) <= max_w then best = cand; lo = mid + 1 else hi = mid - 1 end
    end
    return best
end
M.FitText = FitText

-- 배지용 작은 글씨 (현재 글꼴 그대로, 크기만 78%)
local function PushSmall(ctx)
    local get_font, get_size, push = Fn("ImGui_GetFont"), Fn("ImGui_GetFontSize"), Fn("ImGui_PushFont")
    if not (get_font and get_size and push) then return false end
    local ok_f, font = pcall(get_font, ctx)
    local ok_s, size = pcall(get_size, ctx)
    if not ok_f or not ok_s or type(size) ~= "number" or size <= 0 then return false end
    local ok = pcall(push, ctx, font, math.max(6, size * 0.78))
    return ok
end
local function PopSmall(ctx, pushed)
    if pushed then reaper.ImGui_PopFont(ctx) end
end

-- 이름 + 검색어 강조 (대소문자 무시, 첫 번째 일치 부분)
local function DrawName(ctx, dl, x, y, text, term, col, hcol, max_w)
    local shown = FitText(ctx, text, max_w)
    if shown == "" then return 0 end
    local s, e
    if term and term ~= "" then
        local limit = (shown ~= text) and (#shown - 3) or #text
        s, e = text:lower():find(term, 1, true)
        if s and e > limit then e = limit end
        if s and s > limit then s = nil end
    end
    if not s then
        reaper.ImGui_DrawList_AddText(dl, x, y, col, shown)
        return TextW(ctx, shown)
    end
    local cx = x
    local function Seg(str, c)
        if str ~= "" then
            reaper.ImGui_DrawList_AddText(dl, cx, y, c, str)
            cx = cx + TextW(ctx, str)
        end
    end
    local limit = (shown ~= text) and (#shown - 3) or #text
    Seg(text:sub(1, s - 1), col)
    Seg(text:sub(s, e), hcol)
    Seg(text:sub(e + 1, limit), col)
    if shown ~= text then Seg("...", col) end
    return cx - x
end

local function DrawBadge(ctx, dl, P, S, x, y_mid, w, text, fill)
    local small = PushSmall(ctx)
    local tw, th = reaper.ImGui_CalcTextSize(ctx, text)
    local h = th + 6 * S
    local y1 = y_mid - h / 2
    local shown = FitText(ctx, text, w - 8 * S)
    tw = TextW(ctx, shown)
    if fill then
        reaper.ImGui_DrawList_AddRectFilled(dl, x, y1, x + w, y1 + h, fill, 4 * S)
        reaper.ImGui_DrawList_AddText(dl, x + (w - tw) / 2, y1 + 3 * S, P.base, shown)
    else
        reaper.ImGui_DrawList_AddRect(dl, x, y1, x + w, y1 + h, P.badge_line, 4 * S, 0, 1)
        reaper.ImGui_DrawList_AddText(dl, x + (w - tw) / 2, y1 + 3 * S, P.badge_text, shown)
    end
    PopSmall(ctx, small)
end

-- 배지 열 너비: 샘플(고정 목록)이 있으면 그것으로, 없으면 행 전체에서 한 번 계산해 캐시
local function BadgeColumnW(ctx, st, o, S, max_w)
    local font_size = Fn("ImGui_GetFontSize") and reaper.ImGui_GetFontSize(ctx) or 0
    local source = o.badge_samples or o.key or ""
    if st.badge_source ~= source or st.badge_font ~= font_size then
        local small = PushSmall(ctx)
        local w = 0
        if o.badge_samples then
            for _, b in ipairs(o.badge_samples) do w = math.max(w, TextW(ctx, tostring(b))) end
        else
            for i = 1, math.min(o.count, 2000) do
                local row = o.row(i)
                if row and row.badge and row.badge ~= "" then w = math.max(w, TextW(ctx, row.badge)) end
            end
        end
        PopSmall(ctx, small)
        st.badge_source, st.badge_font = source, font_size
        st.badge_w = (w > 0) and math.ceil(w + 14 * S) or 0
    end
    return math.min(st.badge_w or 0, max_w)
end

----------------------------------------------------------
-- 열(column) 레이아웃
--  o.columns = { {samples = {...}, color = "text"|"muted", flex = true}, ... }
--  o.right_from = n  : n번째 열부터는 오른쪽 끝에 모아 붙인다 (각 열은 왼쪽 정렬)
--  row.cols = { "열1", "열2", ... }
--  * 모든 행이 같은 열 위치를 쓰므로 글자 길이와 상관없이 열 시작점이 반듯하게 맞는다
--  * 열 너비는 samples(전체 목록) 중 가장 긴 글자 기준 → 입력 중에도 흔들리지 않는다
--  * 왼쪽 그룹의 마지막 열은 남는 공간을 모두 쓴다 (flex)
----------------------------------------------------------
local COL_MIN_FLEX = 70   -- 왼쪽 마지막(가변) 열의 최소 너비 (배율 적용 전)

local function ColumnWidths(ctx, st, o, S)
    local font_size = Fn("ImGui_GetFontSize") and reaper.ImGui_GetFontSize(ctx) or 0
    st.col_cache = st.col_cache or {}
    local widths = {}
    for k, col in ipairs(o.columns) do
        local c = st.col_cache[k]
        local source = col.samples or o.key or ""
        if not c or c.source ~= source or c.font ~= font_size then
            local w = 0
            if col.samples then
                for _, s in ipairs(col.samples) do w = math.max(w, TextW(ctx, tostring(s))) end
            else
                for i = 1, math.min(o.count, 2000) do
                    local row = o.row(i)
                    local s = row and row.cols and row.cols[k]
                    if s and s ~= "" then w = math.max(w, TextW(ctx, s)) end
                end
            end
            c = { source = source, font = font_size, w = math.ceil(w) }
            st.col_cache[k] = c
        end
        widths[k] = c.w
    end
    return widths
end

-- 행 하나 기준의 열 시작 x(행 왼쪽에서의 거리)와 너비. 모든 행이 이 값을 공유한다.
local function ColumnLayout(ctx, st, o, S, inner_w, text_left)
    local cols = o.columns
    local n = #cols
    local gap = math.floor(24 * S)
    local widths = ColumnWidths(ctx, st, o, S)
    local right_edge = inner_w - 12 * S
    local rf = math.min(o.right_from or (n + 1), n + 1)
    local lay = { x = {}, w = {}, gap = gap }

    -- 오른쪽 그룹: 오른쪽 끝에 붙이되 각 열은 왼쪽 정렬
    local right_total = 0
    for k = rf, n do right_total = right_total + widths[k] + ((k > rf) and gap or 0) end
    local min_left = text_left + COL_MIN_FLEX * S + gap
    local available = math.max(0, right_edge - min_left)
    local scale = (right_total > available and right_total > 0) and (available / right_total) or 1
    local rx = right_edge
    for k = n, rf, -1 do
        local w = math.floor(widths[k] * scale)
        rx = rx - w
        lay.x[k], lay.w[k] = rx, w
        rx = rx - gap
    end
    local left_limit = (rf <= n) and (rx) or right_edge  -- 왼쪽 그룹이 끝날 수 있는 x

    -- 왼쪽 그룹: 앞에서부터 측정한 너비대로, 마지막 열은 남는 공간 전부
    local x = text_left
    for k = 1, rf - 1 do
        local w
        if k == rf - 1 and (rf <= n or cols[k].flex) then
            w = math.max(0, left_limit - x)
        else
            w = math.min(widths[k], math.max(0, left_limit - x))
        end
        lay.x[k], lay.w[k] = x, w
        x = x + w + gap
    end
    lay.left_end = x   -- 오른쪽 설명(detail)이 시작할 수 있는 최소 x
    return lay
end

local function DrawTooltip(ctx, P, S, text)
    local R = reaper
    R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowPadding(), 12 * S, 9 * S)
    if R.ImGui_BeginTooltip(ctx) then
        R.ImGui_PushTextWrapPos(ctx, R.ImGui_GetCursorPosX(ctx) + 420 * S)
        R.ImGui_Text(ctx, text)
        R.ImGui_PopTextWrapPos(ctx)
        R.ImGui_EndTooltip(ctx)
    end
    R.ImGui_PopStyleVar(ctx, 1)
end

----------------------------------------------------------
-- 행
----------------------------------------------------------
local function DrawRow(ctx, P, S, o, i, row, row_h, width, child_hov, selected, badge_w, lay)
    local R = reaper
    local dl = R.ImGui_GetWindowDrawList(ctx)
    local x, y = R.ImGui_GetCursorScreenPos(ctx)
    local clicked = R.ImGui_InvisibleButton(ctx, "##mini_row_" .. i, math.max(1, width), row_h)
    local hovered = child_hov and R.ImGui_IsItemHovered(ctx)
    local line_h = R.ImGui_GetTextLineHeight(ctx)
    local y_mid = y + row_h / 2

    if selected then
        R.ImGui_DrawList_AddRectFilled(dl, x, y, x + width, y + row_h, P.row_sel)
    elseif hovered then
        R.ImGui_DrawList_AddRectFilled(dl, x, y, x + width, y + row_h, P.row_hover)
    end
    R.ImGui_DrawList_AddLine(dl, x, y + row_h - 0.5, x + width, y + row_h - 0.5, P.row_border, 1)
    if selected then
        R.ImGui_DrawList_AddRectFilled(dl, x, y, x + 3 * S, y + row_h, P.accent)
    end

    local left = x + 12 * S
    if badge_w > 0 then
        if row.badge and row.badge ~= "" then
            DrawBadge(ctx, dl, P, S, left, y_mid, badge_w, row.badge, row.badge_fill)
        end
        left = left + badge_w + 10 * S
    end
    local right = x + width - 12 * S
    local text_y = y + (row_h - line_h) / 2

    -- 열 레이아웃: 모든 행이 같은 열 위치 (설명은 오른쪽 정렬, 남는 공간 안에서)
    if lay and row.cols then
        for k = 1, #o.columns do
            local s = tostring(row.cols[k] or "")
            if s ~= "" and lay.w[k] > 0 then
                local col = o.columns[k]
                local c = (col.color == "muted") and P.muted or P.text
                DrawName(ctx, dl, x + lay.x[k], text_y, s, o.highlight, c, P.hl, lay.w[k])
            end
        end
        local detail = tostring(row.detail or "")
        if detail ~= "" then
            local shown = FitText(ctx, detail, right - (x + lay.left_end))
            if shown ~= "" then
                R.ImGui_DrawList_AddText(dl, right - TextW(ctx, shown), text_y, P.muted, shown)
            end
        end
        if hovered and row.tooltip and row.tooltip ~= "" then
            local tip_ok = true
            local f = Flag("HoveredFlags_ForTooltip")
            if f ~= 0 then tip_ok = R.ImGui_IsItemHovered(ctx, f) end
            if tip_ok then DrawTooltip(ctx, P, S, row.tooltip) end
        end
        return clicked
    end

    -- 오른쪽 설명 (흐린 색, 최대 너비의 약 45%)
    local detail = tostring(row.detail or "")
    if detail ~= "" then
        local max_d = math.max(0, math.min(TextW(ctx, detail), (right - left) * (o.detail_ratio or 0.45)))
        local shown = FitText(ctx, detail, max_d)
        if shown ~= "" then
            local dw = TextW(ctx, shown)
            R.ImGui_DrawList_AddText(dl, right - dw, text_y, P.muted, shown)
            right = right - dw - 16 * S
        end
    end

    -- 이름 (+ 보조 텍스트)
    local name_w = DrawName(ctx, dl, left, text_y, tostring(row.name or ""), o.highlight,
        row.name_col or P.text, P.hl, right - left)
    local sub = tostring(row.sub or "")
    if sub ~= "" then
        local sx = left + name_w + 10 * S
        local shown = FitText(ctx, sub, right - sx)
        if shown ~= "" then R.ImGui_DrawList_AddText(dl, sx, text_y, P.muted, shown) end
    end
    return clicked
end

----------------------------------------------------------
-- 팝업 그리기
----------------------------------------------------------
function M.Draw(ctx, st, o)
    local R = reaper
    local P = o.palette or M.Palette()
    local n = math.max(0, math.floor(tonumber(o.count) or 0))
    local line_h = R.ImGui_GetTextLineHeight(ctx)
    local S = o.scale or math.max(0.75, line_h / 15)
    local row_h = o.row_h or math.floor(line_h * 2.0 + 0.5)
    local max_rows = o.max_rows or 8
    local list_h
    if n > 0 then
        list_h = math.min(n, max_rows) * row_h
    else
        list_h = math.floor(36 * S + line_h)
    end
    local width = math.max(160, math.floor(tonumber(o.w) or 400))
    local border = 1

    -- 목록 내용이 바뀌면 스크롤을 처음으로
    if st.key ~= o.key then
        st.key = o.key
        st.reset_scroll = true
    end

    local flags = Flag("WindowFlags_NoTitleBar") | Flag("WindowFlags_NoResize") | Flag("WindowFlags_NoMove")
        | Flag("WindowFlags_NoCollapse") | Flag("WindowFlags_NoSavedSettings")
        | Flag("WindowFlags_NoFocusOnAppearing") | Flag("WindowFlags_NoNav")
        | Flag("WindowFlags_NoDocking") | Flag("WindowFlags_NoScrollbar")
        | Flag("WindowFlags_NoScrollWithMouse")
    if o.topmost ~= false then flags = flags | Flag("WindowFlags_TopMost") end
    local auto_h = o.footer ~= nil
    if auto_h then
        -- 아래 고정 영역(footer)이 있으면 높이는 내용에 맞추고 너비는 고정
        flags = flags | Flag("WindowFlags_AlwaysAutoResize")
        R.ImGui_SetNextWindowSizeConstraints(ctx, width, 0, width, 100000)
    else
        R.ImGui_SetNextWindowSize(ctx, width, list_h + border * 2, Flag("Cond_Always"))
    end
    R.ImGui_SetNextWindowPos(ctx, o.x or 0, (o.y or 0) + (o.gap or 4 * S), Flag("Cond_Always"))

    R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowPadding(), border, border)
    R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowBorderSize(), border)
    R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowRounding(), 0)
    R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_ItemSpacing(), 0, 0)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_WindowBg(), P.list_bg)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(), P.row_border)
    local visible = R.ImGui_Begin(ctx, o.id or "##jkk_mini_popup", nil, flags)
    R.ImGui_PopStyleColor(ctx, 2)
    R.ImGui_PopStyleVar(ctx, 4)

    local res = { clicked = nil, focused = false, hovered = false, rect = nil }
    if visible then
        res.focused = R.ImGui_IsWindowFocused(ctx, Flag("FocusedFlags_RootAndChildWindows"))
        res.hovered = R.ImGui_IsWindowHovered(ctx, Flag("HoveredFlags_RootAndChildWindows")
            | Flag("HoveredFlags_AllowWhenBlockedByActiveItem"))

        -- 목록
        R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ChildBg(), P.list_bg)
        R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowPadding(), 0, 0)
        R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_ItemSpacing(), 0, 0)
        local list_w = width - border * 2
        local list_visible, list_entered = BeginChildSafe(ctx, "##mini_list", list_w, list_h, 0, 0)
        if list_visible then
            local child_hov = R.ImGui_IsWindowHovered(ctx)
            if n == 0 then
                local msg = tostring(o.empty_text or "No matches")
                local tw = TextW(ctx, msg)
                R.ImGui_SetCursorPos(ctx, math.max(8, (list_w - tw) / 2), (list_h - line_h) / 2)
                R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), P.muted)
                R.ImGui_Text(ctx, msg)
                R.ImGui_PopStyleColor(ctx, 1)
            else
                local total_h = n * row_h
                local scrollbar = 0
                if total_h > list_h then
                    local ok, v = pcall(R.ImGui_GetStyleVar, ctx, R.ImGui_StyleVar_ScrollbarSize())
                    scrollbar = (ok and type(v) == "number") and v or 14
                end
                local inner_w = math.floor(list_w - scrollbar)

                local scroll_y = R.ImGui_GetScrollY(ctx)
                if st.reset_scroll then
                    scroll_y = 0
                    R.ImGui_SetScrollY(ctx, 0)
                    st.reset_scroll = false
                end
                -- 선택 행이 보이도록 필요한 만큼만 스크롤 (가운데로 튀지 않음)
                local sel = tonumber(o.selected) or 0
                if o.ensure_visible and sel >= 1 and sel <= n then
                    local top, bottom = (sel - 1) * row_h, sel * row_h
                    if top < scroll_y then
                        scroll_y = top
                        R.ImGui_SetScrollY(ctx, scroll_y)
                    elseif bottom > scroll_y + list_h then
                        scroll_y = bottom - list_h
                        R.ImGui_SetScrollY(ctx, scroll_y)
                    end
                end

                local badge_w = BadgeColumnW(ctx, st, o, S, inner_w * 0.35)
                local lay = nil
                if o.columns and #o.columns > 0 then
                    local text_left = 12 * S + ((badge_w > 0) and (badge_w + 10 * S) or 0)
                    lay = ColumnLayout(ctx, st, o, S, inner_w, text_left)
                end
                local first = math.max(1, math.floor(scroll_y / row_h) + 1)
                local last = math.min(n, math.floor((scroll_y + list_h) / row_h) + 1)
                for i = first, last do
                    local row = o.row(i)
                    if row then
                        R.ImGui_SetCursorPos(ctx, 0, (i - 1) * row_h)
                        if DrawRow(ctx, P, S, o, i, row, row_h, inner_w, child_hov, i == sel, badge_w, lay) then
                            res.clicked = i
                        end
                    end
                end
                R.ImGui_SetCursorPos(ctx, 0, total_h)
                R.ImGui_Dummy(ctx, 1, 0)
            end
        end
        if list_entered then R.ImGui_EndChild(ctx) end
        R.ImGui_PopStyleVar(ctx, 2)
        R.ImGui_PopStyleColor(ctx, 1)

        -- 아래 고정 영역 (옵션/버튼 등): 목록과 1px 선으로 구분
        if o.footer then
            local dl = R.ImGui_GetWindowDrawList(ctx)
            local fx, fy = R.ImGui_GetCursorScreenPos(ctx)
            R.ImGui_DrawList_AddLine(dl, fx, fy, fx + list_w, fy, P.row_border, 1)
            local child_flags = Flag("ChildFlags_AutoResizeY") | Flag("ChildFlags_AlwaysUseWindowPadding")
            R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ChildBg(), P.header_bg)
            R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowPadding(), 10 * S, 8 * S)
            R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_ItemSpacing(), 8 * S, 6 * S)
            local auto_child = Flag("ChildFlags_AutoResizeY") ~= 0
            local footer_visible, footer_entered = BeginChildSafe(ctx, "##mini_footer", list_w,
                auto_child and 0 or (o.footer_h or 120), child_flags, 0)
            if footer_visible then
                -- pcall로 감싸지 않는다: 중간에 실패하면 Push/Begin 짝이 어긋나 더 큰 오류가 된다
                o.footer(ctx, P)
            end
            if footer_entered then R.ImGui_EndChild(ctx) end
            R.ImGui_PopStyleVar(ctx, 2)
            R.ImGui_PopStyleColor(ctx, 1)
        end

        local wx, wy = R.ImGui_GetWindowPos(ctx)
        local ww, wh = R.ImGui_GetWindowSize(ctx)
        res.rect = { x = wx, y = wy, w = ww, h = wh }
    end
    R.ImGui_End(ctx)
    return res
end

return M
