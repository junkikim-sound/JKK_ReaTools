--========================================================
-- @title JKK_Search_UI
-- @author Junki Kim
-- @noindex
-- JKK Search 화면 구성
--  [헤더]   JKK Search vX  (상태)    N results [≡][▤]  [⟳][⚙][◧][⌄][✕]
--  [검색줄] [All ⌄] (🔍 검색어 ............................................ ✕)
--  ── 아래는 접기/펼치기 (기본 접힘, 펼침 상태는 기억) ──
--  [본문]   사이드 패널(좌, 너비 조절) ┃ RECENT / RESULTS 결과 목록
--           All Results / Recent / Favorites / New
--           BROWSE  : Effects(Category, Developers) / Instruments / FX Chains / Track Templates / Actions
--           PROJECT : Tracks / Items / Markers & Regions
--           TAGS [+]: 사용자 태그 (우클릭: Rename / Duplicate / Delete, 결과를 드롭하면 태그에 추가)
--           [ Insert  on Track 19 ][⌄]
--  결과 행:  [♥][ VST3 ] 이름 ........ 제조사 [⋮]   (detailed 보기: 제조사가 이름 아래)
--  * 다중 선택: Ctrl+클릭, Shift+클릭, Shift+↑↓, ♥/배지 열이나 빈 곳에서 드래그(마키)
--  * 결과(들)를 REAPER 트랙/아이템 위에 드롭하면 그 대상에 삽입, TAGS 항목에 드롭하면 태그에 추가
--  * 배지 클릭 = 타입 필터, 제조사 클릭 = 사이드 패널의 해당 Developer 선택
--========================================================

local M = {}

function M.Create(deps)
local RPR     = reaper
local Theme   = deps.theme
local Store   = deps.store
local Index   = deps.index
local Query   = deps.query
local Actions = deps.actions
local Library = deps.library
local MB      = deps.mb          -- JKK_Search_MediaBrowser (없으면 nil)

-- JKK MediaBrowser 현재 탭 검색 단축키 (설정에서 변경)
local MB_KEYS = {
    { id = "shift_enter",      label = "Shift+Enter" },
    { id = "ctrl_enter",       label = "Ctrl+Enter" },
    { id = "alt_enter",        label = "Alt+Enter" },
    { id = "ctrl_shift_enter", label = "Ctrl+Shift+Enter" },
}
local Sel     = deps.sel
local VERSION = deps.version or ""

local UI = {}

----------------------------------------------------------
-- 상수
----------------------------------------------------------
local POPUP_SETTINGS   = "##jkk_search_settings"
local POPUP_ROW_MENU   = "##jkk_search_row_menu"
local POPUP_TARGET     = "##jkk_search_target"
local POPUP_FORMAT     = "##jkk_search_format_popup"
local POPUP_TAG_MENU   = "##jkk_search_tag_menu"
local POPUP_TAG_RENAME = "##jkk_search_tag_rename"
local POPUP_TAG_DELETE = "##jkk_search_tag_delete"
local POPUP_NEW_MENU   = "##jkk_search_new_menu"
local DRAG_TYPE        = "JKK_SEARCH_ENTRY"

-- 검색창 왼쪽 타입 필터 (플러그인 포맷 + 항목 종류)
local FORMATS = {
    { id = "all",      label = "All"      },
    { id = "VST3",     label = "VST3"     },
    { id = "VST",      label = "VST"      },
    { id = "CLAP",     label = "CLAP"     },
    { id = "JS",       label = "JS"       },
    { id = "other",    label = "Other FX" },
    { id = "chain",    label = "Chain"    },
    { id = "template", label = "Template" },
    { id = "action",   label = "Action"   },
    { id = "track",    label = "Track"    },
    { id = "item",     label = "Item"     },
    { id = "marker",   label = "Marker"   },
    { id = "project",  label = "Project"  },
}

local KIND_TO_FILTER = {
    chain = "chain", template = "template", action = "action", track = "track",
    item = "item", marker = "marker", region = "marker", project = "project",
}
local FX_FORMATS = { VST3 = true, VST = true, CLAP = true, JS = true }

local BADGE_SAMPLES = {
    "VST", "VST3", "VSTi", "VST3i", "CLAP", "CLAPi", "JS", "CHAIN", "TEMPLATE",
    "ACTION", "TRACK", "ITEM", "MARKER", "REGION", "PROJECT", "LV2", "LV2i", "FOLDER", "UCS",
}

local KIND_LABEL = {
    fx = "FX", chain = "FX", template = "TRACK", action = "ACTION", track = "TRACK",
    item = "ITEM", marker = "MARKER", region = "REGION", project = "PROJECT",
    mbfolder = "MEDIA", mbucs = "MEDIA",
}

local FONT_MIN, FONT_MAX = 8, 24

----------------------------------------------------------
-- 상태
----------------------------------------------------------
local S             = 1.0       -- 글자 배율 = font_size / 테마 기본 크기 (매 프레임 갱신)
local query         = ""
local scope         = Store.Get("last_scope") or "all"
local format        = "all"
local results       = {}
local recent_count  = 0
local sel           = 1         -- 키보드 커서 행
local anchor        = 1         -- Shift 범위 선택 기준 행
local msel          = {}        -- 다중 선택: entry -> true
local msel_count    = 0
local last_sig      = nil
local last_qkey     = nil
local scroll_to_sel = false
local scroll_to_top = false
local focus_search  = true

local expanded      = Store.Get("expanded") and true or false
local collapsed_h   = nil
local sidebar_w     = Store.Get("sidebar_w")

local status_msg, status_ok, status_time = nil, true, 0
local pending         = nil
local menu_entry      = nil
local open_menu_req   = false
local open_target_req = false

local drag = { entries = nil, target = nil, label = nil }
local drag_consumed = false
local marquee = { pending = false, active = false, moved = false, sx = 0, sy = 0, base = nil, from_void = false }

local tree_open = { browse = true, project = true, tags = true, effects = true, cat = false, dev = false }
-- 저장된 펼침 상태 복원
for k, v in (Store.Get("tree_open") or ""):gmatch("([%w_]+)=([01])") do
    if tree_open[k] ~= nil then tree_open[k] = (v == "1") end
end
local function SerializeTree()
    local keys = {}
    for k in pairs(tree_open) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. (tree_open[k] and "1" or "0") end
    return table.concat(parts, ";")
end
local saved_tree = SerializeTree()
local sidebar_scroll_to = nil
local tag_menu_id, open_tag_menu_req = nil, false
local rename = { id = nil, buf = "", focus = false, req = false }
local delete_tag = { id = nil, req = false }
local open_new_menu_req = false

local was_building = true
local refresh_requested = false

local badge_col = { scale = nil, w = 0 }
local was_focused, unfocus_since = false, nil

-- 존재하지 않는 항목으로 저장돼 있으면 All 로
if scope == "projects" or scope == "" then scope = "all" end
if scope:match("^tag:") and not (Library and Library.FindTag(scope:sub(5))) then scope = "all" end

----------------------------------------------------------
-- 색상 유틸 / 팔레트
----------------------------------------------------------
local function Blend(c1, c2, t, alpha)
    if not RPR.ImGui_ColorConvertU32ToDouble4 then return c1 end
    local r1, g1, b1, a1 = RPR.ImGui_ColorConvertU32ToDouble4(c1)
    local r2, g2, b2, a2 = RPR.ImGui_ColorConvertU32ToDouble4(c2)
    local a = alpha and (alpha / 255) or (a1 + (a2 - a1) * t)
    return RPR.ImGui_ColorConvertDouble4ToU32(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t, a)
end

local function WithAlpha(col, alpha)
    return (col & 0xFFFFFF00) | (alpha & 0xFF)
end

local function IsDark(col)
    if not RPR.ImGui_ColorConvertU32ToDouble4 then return true end
    local r, g, b = RPR.ImGui_ColorConvertU32ToDouble4(col)
    return (0.299 * r + 0.587 * g + 0.114 * b) < 0.5
end

local function BuildPalette()
    local base   = Theme.GetColor("base_bg")
    local ctrl   = Theme.GetColor("control_bg")
    local text   = Theme.GetColor("text_main")
    local accent = Theme.GetColor("accent_main")
    local dark   = IsDark(base)
    local black  = 0x000000FF
    return {
        base        = base,
        ctrl        = ctrl,
        text        = text,
        accent      = accent,
        important   = Theme.GetColor("accent"),
        muted       = Blend(text, base, 0.42),
        faint       = Blend(text, base, 0.62),
        list_bg     = Blend(base, black, dark and 0.18 or 0.05, 255),
        sidebar_bg  = base,
        row_hover   = Blend(base, ctrl, 0.55, 255),
        row_sel     = Blend(base, ctrl, 0.95, 255),
        row_msel    = Blend(Blend(base, ctrl, 0.95, 255), accent, 0.16, 255),
        row_border  = Blend(base, ctrl, 0.45, 255),
        header_bg   = Blend(base, ctrl, 0.25, 255),
        frame       = ctrl,
        frame_hover = Blend(ctrl, text, 0.08, 255),
        badge_line  = Blend(text, base, 0.60),
        badge_hover = Blend(text, base, 0.25),
        badge_text  = Blend(text, base, 0.28),
        icon_bg     = Blend(base, ctrl, 0.9, 255),
        icon_line   = Blend(ctrl, text, 0.18, 255),
        hl          = accent,
        fav         = accent,
        warn        = dark and 0xF06A6AFF or 0xB83232FF,
        box_bg      = Blend(base, ctrl, 0.75, 255),
        box_hover   = Blend(base, ctrl, 1.0, 255),
    }
end

----------------------------------------------------------
-- 텍스트 / 입력 유틸
----------------------------------------------------------
local function TextW(ctx, s) return (RPR.ImGui_CalcTextSize(ctx, s)) end

-- UTF-8 안전 말줄임
local function FitText(ctx, text, max_w)
    if max_w <= 0 then return "" end
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

-- 검색어 일치 부분을 강조해서 그리기
local function DrawHighlighted(ctx, dl, x, y, text, ranges, col, hcol, max_w)
    local shown = FitText(ctx, text, max_w)
    if shown == "" then return end
    local truncated = (shown ~= text)
    local limit = truncated and (#shown - 3) or #text
    if not ranges then
        RPR.ImGui_DrawList_AddText(dl, x, y, col, shown)
        return
    end
    local cx, pos = x, 1
    local function Seg(s, c)
        if s ~= "" then
            RPR.ImGui_DrawList_AddText(dl, cx, y, c, s)
            cx = cx + TextW(ctx, s)
        end
    end
    for _, r in ipairs(ranges) do
        local s, e = r[1], math.min(r[2], limit)
        if s > limit then break end
        if s >= pos then
            Seg(text:sub(pos, s - 1), col)
            Seg(text:sub(s, e), hcol)
            pos = e + 1
        end
    end
    Seg(text:sub(pos, limit), col)
    if truncated then Seg("...", col) end
end

local function IsCtrlDown(ctx)  return RPR.ImGui_IsKeyDown(ctx, RPR.ImGui_Mod_Ctrl()) end
local function IsShiftDown(ctx) return RPR.ImGui_IsKeyDown(ctx, RPR.ImGui_Mod_Shift()) end
local function IsAltDown(ctx)   return RPR.ImGui_IsKeyDown(ctx, RPR.ImGui_Mod_Alt()) end

local function Pressed(ctx, key, rep)
    return RPR.ImGui_IsKeyPressed(ctx, key, rep ~= false)
end

local function StyleVec(ctx, var)
    local ok, x, y = pcall(RPR.ImGui_GetStyleVar, ctx, var)
    if ok then return x or 0, y or 0 end
    return 0, 0
end

local function ScrollbarW(ctx)
    local ok, v = pcall(RPR.ImGui_GetStyleVar, ctx, RPR.ImGui_StyleVar_ScrollbarSize())
    if ok and type(v) == "number" and v > 0 then return v end
    return 14 * S
end

local function MouseIn(ctx, x1, y1, x2, y2)
    local mx, my = RPR.ImGui_GetMousePos(ctx)
    return mx >= x1 and mx <= x2 and my >= y1 and my <= y2
end

-- 키보드 내비게이션을 끈 상태이므로 Esc로 팝업 닫기를 직접 처리한다.
local esc_close_popup = false
local function AnyPopupOpen(ctx)
    return RPR.ImGui_IsPopupOpen(ctx, "",
        RPR.ImGui_PopupFlags_AnyPopupId() | RPR.ImGui_PopupFlags_AnyPopupLevel())
end
local function ConsumeEscClose(ctx)
    if esc_close_popup then
        esc_close_popup = false
        RPR.ImGui_CloseCurrentPopup(ctx)
    end
end

----------------------------------------------------------
-- 글자 크기 (정수 px)
----------------------------------------------------------
local function BaseFontSize()
    return tonumber(Theme.GetColor("font_base_size")) or 13
end

local function CurrentFontSize()
    local fs = tonumber(Store.Get("font_size")) or 0
    if fs <= 0 then return BaseFontSize() end
    return math.floor(fs + 0.5)
end

function UI.ComputeScale()
    return CurrentFontSize() / BaseFontSize()
end

function UI.SetFontSize(px)
    px = math.max(FONT_MIN, math.min(FONT_MAX, math.floor(px + 0.5)))
    Store.Set("font_size", (px == BaseFontSize()) and 0 or px)
end

----------------------------------------------------------
-- 직접 그리는 아이콘 (폰트 글리프에 의존하지 않음)
----------------------------------------------------------
local function DrawChevron(dl, cx, cy, r, dir, col, th)
    th = th or 1.6 * S
    if dir == "down" then
        RPR.ImGui_DrawList_AddLine(dl, cx - r, cy - r * 0.5, cx, cy + r * 0.5, col, th)
        RPR.ImGui_DrawList_AddLine(dl, cx, cy + r * 0.5, cx + r, cy - r * 0.5, col, th)
    elseif dir == "up" then
        RPR.ImGui_DrawList_AddLine(dl, cx - r, cy + r * 0.5, cx, cy - r * 0.5, col, th)
        RPR.ImGui_DrawList_AddLine(dl, cx, cy - r * 0.5, cx + r, cy + r * 0.5, col, th)
    else
        RPR.ImGui_DrawList_AddLine(dl, cx - r * 0.5, cy - r, cx + r * 0.5, cy, col, th)
        RPR.ImGui_DrawList_AddLine(dl, cx + r * 0.5, cy, cx - r * 0.5, cy + r, col, th)
    end
end

local ICONS = {}
function ICONS.compact(dl, x, y, s, col)
    local th = 1.6 * S
    for i = 0, 2 do
        local yy = y + s * (0.28 + i * 0.22)
        RPR.ImGui_DrawList_AddCircleFilled(dl, x + s * 0.24, yy, s * 0.05 + 0.5, col)
        RPR.ImGui_DrawList_AddLine(dl, x + s * 0.36, yy, x + s * 0.80, yy, col, th)
    end
end
function ICONS.detailed(dl, x, y, s, col)
    local th = 1.6 * S
    for i = 0, 1 do
        local yy = y + s * (0.32 + i * 0.36)
        RPR.ImGui_DrawList_AddCircleFilled(dl, x + s * 0.26, yy, s * 0.09, col)
        RPR.ImGui_DrawList_AddLine(dl, x + s * 0.42, yy - s * 0.06, x + s * 0.80, yy - s * 0.06, col, th)
        RPR.ImGui_DrawList_AddLine(dl, x + s * 0.42, yy + s * 0.08, x + s * 0.66, yy + s * 0.08, col, th)
    end
end
function ICONS.sidebar(dl, x, y, s, col)   -- 왼쪽 패널
    local x1, y1, x2, y2 = x + s * 0.2, y + s * 0.24, x + s * 0.8, y + s * 0.76
    RPR.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, col, 2 * S, 0, 1.5 * S)
    RPR.ImGui_DrawList_AddRectFilled(dl, x1, y1, x1 + (x2 - x1) * 0.38, y2, col, 2 * S)
end
function ICONS.expand(dl, x, y, s, col)
    DrawChevron(dl, x + s / 2, y + s / 2, s * 0.2, "down", col)
end
function ICONS.collapse(dl, x, y, s, col)
    DrawChevron(dl, x + s / 2, y + s / 2, s * 0.2, "up", col)
end
function ICONS.refresh(dl, x, y, s, col)
    local cx, cy, r = x + s / 2, y + s / 2, s * 0.25
    RPR.ImGui_DrawList_PathArcTo(dl, cx, cy, r, -math.pi * 0.35, math.pi * 1.25, 20)
    RPR.ImGui_DrawList_PathStroke(dl, col, 0, 1.6 * S)
    local ax, ay = cx + r * math.cos(-math.pi * 0.35), cy + r * math.sin(-math.pi * 0.35)
    local a = s * 0.12
    RPR.ImGui_DrawList_AddTriangleFilled(dl, ax - a, ay - a * 0.9, ax + a * 0.9, ay - a * 0.2, ax + a * 0.1, ay + a, col)
end
function ICONS.plus(dl, x, y, s, col)
    local cx, cy, r = x + s / 2, y + s / 2, s * 0.22
    RPR.ImGui_DrawList_AddLine(dl, cx - r, cy, cx + r, cy, col, 1.6 * S)
    RPR.ImGui_DrawList_AddLine(dl, cx, cy - r, cx, cy + r, col, 1.6 * S)
end
function ICONS.close(dl, x, y, s, col)
    local cx, cy, r = x + s / 2, y + s / 2, s * 0.2
    RPR.ImGui_DrawList_AddLine(dl, cx - r, cy - r, cx + r, cy + r, col, 1.8 * S)
    RPR.ImGui_DrawList_AddLine(dl, cx - r, cy + r, cx + r, cy - r, col, 1.8 * S)
end
ICONS.clear = ICONS.close
function ICONS.settings(dl, x, y, s, col)
    -- 톱니바퀴: 원 + 8개의 톱니
    local cx, cy = x + s / 2, y + s / 2
    local r1, r2 = s * 0.17, s * 0.30
    for k = 0, 7 do
        local a = k * math.pi / 4
        RPR.ImGui_DrawList_AddLine(dl, cx + math.cos(a) * r1, cy + math.sin(a) * r1,
            cx + math.cos(a) * r2, cy + math.sin(a) * r2, col, 2.6 * S)
    end
    RPR.ImGui_DrawList_AddCircle(dl, cx, cy, s * 0.20, col, 20, 2.2 * S)
end
function ICONS.search(dl, x, y, s, col)
    local r = s * 0.32
    local cx, cy = x + r + 1, y + r + 1
    RPR.ImGui_DrawList_AddCircle(dl, cx, cy, r, col, 16, 1.6 * S)
    local d = r * 0.72
    RPR.ImGui_DrawList_AddLine(dl, cx + d, cy + d, cx + d + r * 0.9, cy + d + r * 0.9, col, 1.8 * S)
end

----------------------------------------------------------
-- PNG 아이콘 (있으면 이미지, 없으면 위의 직접 그린 아이콘 / 자리표시자)
-- 경로: Modules/Icons/JKK_Search/<파일명>.png
-- 흰색(#FFFFFF) + 투명 배경 이미지를 권장: 테마 색으로 틴트되어 그려진다.
-- 파일이 없으면 1.5초마다 다시 확인하므로, 실행 중에 파일을 넣어도 바로 나타난다.
----------------------------------------------------------
local ICON_DIR = ((debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or "") .. "Icons/JKK_Search/"
UI.ICON_DIR = ICON_DIR

local ICON_FILES = {
    -- 사이드 패널
    all         = "Icon_AllResult",
    recent      = "Icon_Recent",
    favorites   = "Icon_Favorites",
    new         = "Icon_New",
    effects     = "Icon_Effects",
    instruments = "Icon_Instruments",
    chains      = "Icon_FXChains",
    templates   = "Icon_TrackTemplates",
    actions     = "Icon_Actions",
    tracks      = "Icon_Tracks",
    items       = "Icon_Items",
    markers     = "Icon_Markers",
    tag         = "Icon_Tag",
    -- 상단 / 검색줄
    compact     = "Icon_ViewCompact",
    detailed    = "Icon_ViewDetailed",
    refresh     = "Icon_Refresh",
    settings    = "Icon_Settings",
    sidebar     = "Icon_SidePanel",
    expand      = "Icon_Expand",
    collapse    = "Icon_Collapse",
    close       = "Icon_Close",
    plus        = "Icon_AddTag",
    search      = "Icon_Search",
    clear       = "Icon_Clear",
}
UI.ICON_FILES = ICON_FILES

local icon_cache = {}

local function GetIcon(ctx, key)
    local file = ICON_FILES[key]
    if not file or not RPR.ImGui_CreateImage then return nil end
    local c = icon_cache[key]
    if c and c.img then
        if not RPR.ImGui_ValidatePtr or RPR.ImGui_ValidatePtr(c.img, "ImGui_Image*") then return c.img end
        c = nil
    end
    local now = RPR.time_precise()
    if c and c.missing and (now - c.checked) < 1.5 then return nil end
    local path = ICON_DIR .. file .. ".png"
    if not RPR.file_exists(path) then
        icon_cache[key] = { missing = true, checked = now }
        return nil
    end
    local ok, img = pcall(RPR.ImGui_CreateImage, path)
    if not ok or not img then
        icon_cache[key] = { missing = true, checked = now }
        return nil
    end
    pcall(RPR.ImGui_Attach, ctx, img)
    icon_cache[key] = { img = img }
    return img
end

-- 아이콘 그리기: (x, y) 기준 s×s 영역. pad 만큼 안쪽에 이미지를 그린다.
-- 반환: 이미지로 그렸으면 true
local function DrawIcon(ctx, dl, key, x, y, s, col, pad)
    local img = GetIcon(ctx, key)
    if img then
        pad = pad or 0
        local ok = pcall(RPR.ImGui_DrawList_AddImage, dl, img, x + pad, y + pad, x + s - pad, y + s - pad,
            0, 0, 1, 1, col)
        if ok then return true end
    end
    if ICONS[key] then ICONS[key](dl, x, y, s, col) end
    return false
end

----------------------------------------------------------
-- 툴팁 (헤더 버튼 등 / 넉넉한 여백)
----------------------------------------------------------
local function HoverTip(ctx, text)
    if not text or text == "" then return end
    local flags = RPR.ImGui_HoveredFlags_ForTooltip and RPR.ImGui_HoveredFlags_ForTooltip()
        or RPR.ImGui_HoveredFlags_DelayNormal()
    if not RPR.ImGui_IsItemHovered(ctx, flags) then return end
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_WindowPadding(), 12 * S, 9 * S)
    if RPR.ImGui_BeginTooltip(ctx) then
        RPR.ImGui_PushTextWrapPos(ctx, RPR.ImGui_GetCursorPosX(ctx) + 380 * S)
        RPR.ImGui_Text(ctx, text)
        RPR.ImGui_PopTextWrapPos(ctx)
        RPR.ImGui_EndTooltip(ctx)
    end
    RPR.ImGui_PopStyleVar(ctx, 1)
end

----------------------------------------------------------
-- 상태 메시지 / 선택 / 실행 요청
----------------------------------------------------------
function UI.SetStatus(ok, msg)
    status_ok, status_msg, status_time = ok and true or false, msg, RPR.time_precise()
end

local function ClearMulti()
    msel, msel_count = {}, 0
end

local function SetMulti(e, on)
    if on and not msel[e] then msel[e] = true; msel_count = msel_count + 1
    elseif not on and msel[e] then msel[e] = nil; msel_count = msel_count - 1 end
end

local function SelectRange(a, b, keep)
    if not keep then ClearMulti() end
    if a > b then a, b = b, a end
    for i = math.max(1, a), math.min(#results, b) do SetMulti(results[i], true) end
end

-- 결과 순서대로 정렬된 선택 목록
local function SelectedEntries()
    local out = {}
    for i = 1, #results do
        if msel[results[i]] then out[#out + 1] = results[i] end
    end
    return out
end

-- 이 행에 대한 동작 대상: 이 행이 다중 선택에 포함되어 있으면 선택 전체, 아니면 이 행만
local function EntriesFor(e)
    if e and msel[e] and msel_count > 1 then return SelectedEntries() end
    return { e }
end

local function IsInsertable(e)
    return e.kind == "fx" or e.kind == "chain" or e.kind == "template"
end

----------------------------------------------------------
-- JKK MediaBrowser 연동
----------------------------------------------------------
local mb_mode = nil   -- 현재 검색어가 MediaBrowser 전용 모드인지: "folder"(@) | "ucs"(!) | nil

local function MBKeyLabel()
    local id = Store.Get("mb_key")
    for _, k in ipairs(MB_KEYS) do if k.id == id then return k.label end end
    return "Shift+Enter"
end

local function MBKeyMatches(ctrl, shift, alt)
    local id = Store.Get("mb_key")
    if id == "ctrl_enter" then return ctrl and not shift and not alt end
    if id == "alt_enter" then return alt and not ctrl and not shift end
    if id == "ctrl_shift_enter" then return ctrl and shift and not alt end
    return shift and not ctrl and not alt
end

-- "실행 후 창 유지(반대 동작)" 단축키 표기: MediaBrowser 단축키와 겹치지 않는 쪽
local function KeepOpenLabel()
    if not MB then return "Shift/Ctrl+Enter" end   -- 연동이 없으면 원래 동작 그대로
    local id = Store.Get("mb_key")
    if id == "shift_enter" then return "Ctrl+Enter" end
    if id == "ctrl_enter" then return "Shift+Enter" end
    return "Shift/Ctrl+Enter"
end

-- entry: 선택된 @폴더 / !UCS 행, 또는 nil (검색어 그대로)
local function RequestMB(entry, keep_toggle)
    if not MB then
        UI.SetStatus(false, "JKK MediaBrowser integration is not available")
        return
    end
    if not MB.Available() then
        UI.SetStatus(false, "JKK MediaBrowser not found next to JKK_ReaTools")
        return
    end
    if (entry == nil or not entry.mb) and query:match("^%s*$") then
        UI.SetStatus(false, "Type something to search in Media Browser")
        return
    end
    local req = MB.BuildRequest(query, (entry and entry.mb) and entry or nil)
    local close = Store.Get("close_after_run")
    if keep_toggle then close = not close end
    pending = { mb = req, close = close }
end

-- 실행 요청: 실제 실행은 메인 루프에서 (창을 닫은 뒤 실행해야 하는 경우가 있으므로)
local function RequestRun(list, opts, keep_toggle)
    if not list or #list == 0 then return end
    if list[1].mb then return RequestMB(list[1], keep_toggle) end
    opts = opts or {}
    local needs_target, has_inst = false, false
    for _, e in ipairs(list) do
        if e.kind == "fx" or e.kind == "chain" then needs_target = true end
        if e.is_instrument then has_inst = true end
    end
    if needs_target and not has_inst and not opts.explicit then
        local t = Actions.ResolveTarget(opts.target_mode, false)
        if t.mode == "none" or t.count == 0 then
            UI.SetStatus(false, "Select a track or item first, or drag the FX onto one")
            return
        end
    end
    local close = Store.Get("close_after_run")
    if keep_toggle then close = not close end
    pending = { entries = list, opts = opts, close = close }
end

function UI.TakePending()
    local p = pending
    pending = nil
    if p and not p.close then focus_search = true end
    return p
end

----------------------------------------------------------
-- 창 크기 연동 (메인 스크립트에서 사용)
----------------------------------------------------------
function UI.IsExpanded() return expanded end
function UI.CollapsedHeight() return collapsed_h or Store.Get("collapsed_h") end
function UI.Scale() return S end

-- 사용자가 직접 펼치거나 접은 상태는 저장 (입력 시 자동 펼침은 저장하지 않음)
local function SetExpanded(v, remember)
    expanded = v and true or false
    if remember then Store.Set("expanded", expanded) end
end

----------------------------------------------------------
-- 결과 갱신
----------------------------------------------------------
local function UpdateResults()
    mb_mode = MB and MB.Mode(query) or nil
    local qkey = query .. "\1" .. scope .. "\1" .. format
    local sig = qkey .. "\1" .. Index.version .. "\1" .. Store.Revision() .. "\1" .. (Library and Library.Revision() or 0)
        .. "\1" .. (mb_mode and MB.Revision() or 0)
    if sig == last_sig then return end
    last_sig = sig

    local prev_entry = results[sel]
    if mb_mode then
        -- ! (UCS) / @ (폴더): JKK MediaBrowser 검색 엔진의 제안 목록
        results, recent_count = MB.Suggest(query), 0
        Query.SetHighlightTerm(MB.Term(query))
    else
        results, recent_count = Query.Run({ query = query, scope = scope, format = format })
    end

    if qkey ~= last_qkey then
        last_qkey = qkey
        sel, anchor = 1, 1
        ClearMulti()
        scroll_to_top = true
    else
        sel = 1
        if prev_entry then
            for i = 1, #results do
                if results[i] == prev_entry then sel = i break end
            end
        end
        -- 결과에서 사라진 다중 선택 항목 정리
        local present = {}
        for i = 1, #results do present[results[i]] = true end
        for e in pairs(msel) do if not present[e] then SetMulti(e, false) end end
    end
    if sel > #results then sel = math.max(1, #results) end
end

local function SetScope(s)
    scope = s
    Store.Set("last_scope", s)
    focus_search = true
end

local function SetFormat(f)
    format = f
    focus_search = true
end

local function FilterForEntry(e)
    if e.kind == "fx" then return FX_FORMATS[e.fx_type] and e.fx_type or "other" end
    return KIND_TO_FILTER[e.kind]
end

-- 결과 행에서 제조사를 클릭: 사이드 패널의 해당 Developer 노드를 선택/표시
local function FocusDeveloper(name)
    if not name or name == "" then return end
    SetScope("dev:" .. name)
    query = ""
    tree_open.browse, tree_open.effects, tree_open.dev = true, true, true
    sidebar_scroll_to = "dev:" .. name
    if not Store.Get("show_sidebar") then Store.Set("show_sidebar", true) end
    if not expanded then SetExpanded(true, false) end
end

local function KeysOf(list)
    local keys = {}
    for _, e in ipairs(list) do
        if not e.mb then keys[#keys + 1] = e.key end   -- MediaBrowser 제안 행은 태그 대상 아님
    end
    return keys
end

local function AddEntriesToTag(tag_id, list)
    local t = Library.FindTag(tag_id)
    if not t then return end
    local n = Library.AddToTag(tag_id, KeysOf(list))
    UI.SetStatus(true, string.format("Added %d to tag \"%s\"", n, t.name))
end

local function OpenRename(tag_id)
    local t = Library.FindTag(tag_id)
    if not t then return end
    rename.id, rename.buf, rename.focus, rename.req = tag_id, t.name, true, true
end

----------------------------------------------------------
-- 헤더
----------------------------------------------------------
-- 아이콘 버튼: PNG 아이콘이 있으면 이미지(버튼 크기의 약 64%), 없으면 직접 그린 아이콘
local function DrawnIconButton(ctx, P, id, size, active, tooltip, icon)
    local x, y = RPR.ImGui_GetCursorScreenPos(ctx)
    local clicked = RPR.ImGui_InvisibleButton(ctx, id, size, size)
    local hov = RPR.ImGui_IsItemHovered(ctx)
    local dl = RPR.ImGui_GetWindowDrawList(ctx)
    if active then
        RPR.ImGui_DrawList_AddRectFilled(dl, x, y, x + size, y + size, P.row_sel, 4 * S)
    elseif hov then
        RPR.ImGui_DrawList_AddRectFilled(dl, x, y, x + size, y + size, P.row_hover, 4 * S)
    end
    DrawIcon(ctx, dl, icon, x, y, size, active and P.accent or (hov and P.text or P.muted), size * 0.18)
    HoverTip(ctx, tooltip)
    return clicked
end

local function DoRefresh()
    local ran, name = Actions.ScanForNewPlugins(Index.GetList("action"))
    refresh_requested = true
    Index.Rebuild()
    UI.SetStatus(true, ran and ("Scanned for new plugins  (" .. name .. ")") or "Re-indexing FX, chains, templates and actions...")
end

local function DrawHeader(ctx, P)
    local close = false
    local start_x = RPR.ImGui_GetCursorPosX(ctx)
    local avail_w = select(1, RPR.ImGui_GetContentRegionAvail(ctx))
    local bs = math.floor(RPR.ImGui_GetFrameHeight(ctx))
    local gap = 2
    local group_gap = 8 * S
    local buttons_w = bs * 7 + gap * 5 + group_gap

    local count_text
    if Index.building and #results == 0 then count_text = "Indexing..."
    else count_text = string.format("%d result%s", #results, #results == 1 and "" or "s") end
    if msel_count > 0 then count_text = string.format("%d selected  ·  ", msel_count) .. count_text end
    local count_w = TextW(ctx, count_text)
    local count_x = start_x + avail_w - buttons_w - 10 * S - count_w

    RPR.ImGui_AlignTextToFramePadding(ctx)
    Theme.PushText(ctx, "accent")
    RPR.ImGui_Text(ctx, "JKK Search")
    Theme.PopText(ctx)
    RPR.ImGui_SameLine(ctx, 0, 8 * S)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), P.faint)
    RPR.ImGui_Text(ctx, "v" .. VERSION)
    RPR.ImGui_PopStyleColor(ctx, 1)

    local msg, col = nil, P.muted
    if status_msg and (RPR.time_precise() - status_time) < 5 then
        msg, col = status_msg, status_ok and P.important or P.warn
    elseif Index.building and Index.status ~= "" then
        msg, col = Index.status, P.faint
    end
    if msg then
        RPR.ImGui_SameLine(ctx, 0, 14 * S)
        local max_w = count_x - RPR.ImGui_GetCursorPosX(ctx) - 12 * S
        local shown = FitText(ctx, msg, max_w)
        if shown ~= "" then
            RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), col)
            RPR.ImGui_Text(ctx, shown)
            RPR.ImGui_PopStyleColor(ctx, 1)
            if shown ~= msg then HoverTip(ctx, msg) end
        end
    end

    RPR.ImGui_SameLine(ctx, 0, 0)
    RPR.ImGui_SetCursorPosX(ctx, math.max(RPR.ImGui_GetCursorPosX(ctx), count_x))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), P.muted)
    RPR.ImGui_Text(ctx, count_text)
    RPR.ImGui_PopStyleColor(ctx, 1)

    local view = Store.Get("view_mode")
    RPR.ImGui_SameLine(ctx, 0, 0)
    RPR.ImGui_SetCursorPosX(ctx, start_x + avail_w - buttons_w)
    if DrawnIconButton(ctx, P, "##jkk_view_compact", bs, view == "compact", "Compact list", "compact") then
        Store.Set("view_mode", "compact")
    end
    RPR.ImGui_SameLine(ctx, 0, gap)
    if DrawnIconButton(ctx, P, "##jkk_view_detailed", bs, view == "detailed", "Detailed list (developer below name)", "detailed") then
        Store.Set("view_mode", "detailed")
    end

    RPR.ImGui_SameLine(ctx, 0, group_gap)
    if DrawnIconButton(ctx, P, "##jkk_search_refresh_btn", bs, false,
        "Refresh: scan for new plugins and re-index", "refresh") then
        DoRefresh()
    end
    RPR.ImGui_SameLine(ctx, 0, gap)
    if DrawnIconButton(ctx, P, "##jkk_search_settings_btn", bs, false, "Settings", "settings") then
        RPR.ImGui_OpenPopup(ctx, POPUP_SETTINGS)
    end
    RPR.ImGui_SameLine(ctx, 0, gap)
    local sb_on = Store.Get("show_sidebar")
    if DrawnIconButton(ctx, P, "##jkk_search_sidebar_btn", bs, sb_on and expanded,
        sb_on and "Hide side panel" or "Show side panel", "sidebar") then
        if not expanded then
            SetExpanded(true, true)
            Store.Set("show_sidebar", true)
        else
            Store.Set("show_sidebar", not sb_on)
        end
    end
    RPR.ImGui_SameLine(ctx, 0, gap)
    if DrawnIconButton(ctx, P, "##jkk_search_expand_btn", bs, false,
        expanded and "Collapse results" or "Expand results", expanded and "collapse" or "expand") then
        SetExpanded(not expanded, true)
        focus_search = true
    end
    RPR.ImGui_SameLine(ctx, 0, gap)
    if DrawnIconButton(ctx, P, "##jkk_search_close_btn", bs, false, "Close (Esc)", "close") then
        close = true
    end
    RPR.ImGui_Separator(ctx)
    return close
end

----------------------------------------------------------
-- 팝업 공통: 여백 확보 + 내용 크기에 맞춤 + 스크롤바 없음
----------------------------------------------------------
local function PopupFlags()
    return RPR.ImGui_WindowFlags_AlwaysAutoResize()
        | RPR.ImGui_WindowFlags_NoScrollbar()
        | RPR.ImGui_WindowFlags_NoScrollWithMouse()
end

local function BeginStyledPopup(ctx, id)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_WindowPadding(), 12 * S, 10 * S)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ItemSpacing(), 8 * S, 6 * S)
    local open = RPR.ImGui_BeginPopup(ctx, id, PopupFlags())
    if not open then
        RPR.ImGui_PopStyleVar(ctx, 2)
        return false
    end
    ConsumeEscClose(ctx)
    return true
end

local function EndStyledPopup(ctx)
    RPR.ImGui_EndPopup(ctx)
    RPR.ImGui_PopStyleVar(ctx, 2)
end

----------------------------------------------------------
-- 검색줄:  [All ⌄] (🔍 ....................................... ✕)
----------------------------------------------------------
local function DrawSearchRow(ctx, P)
    Theme.PushFont(ctx, S * 1.35, "input")
    local line_h = RPR.ImGui_GetTextLineHeight(ctx)
    local pad_y = math.floor(line_h * 0.45)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_FramePadding(), 12 * S, pad_y)
    local frame_h = RPR.ImGui_GetFrameHeight(ctx)
    local avail_w = select(1, RPR.ImGui_GetContentRegionAvail(ctx))
    local gap = 6 * S
    local _, sp_y = StyleVec(ctx, RPR.ImGui_StyleVar_ItemSpacing())

    -- 1) 타입 필터: 직접 만든 드롭다운 (팝업은 내용 크기에 맞춰 스크롤바가 생기지 않음)
    local fmt_label = "All"
    local widest = 0
    for _, f in ipairs(FORMATS) do
        if f.id == format then fmt_label = f.label end
        widest = math.max(widest, TextW(ctx, f.label))
    end
    local combo_w = math.floor(widest + 46 * S)
    local fx0, fy0 = RPR.ImGui_GetCursorScreenPos(ctx)
    if RPR.ImGui_InvisibleButton(ctx, "##jkk_search_format_btn", combo_w, frame_h) then
        RPR.ImGui_OpenPopup(ctx, POPUP_FORMAT)
    end
    local f_hov = RPR.ImGui_IsItemHovered(ctx)
    local dl = RPR.ImGui_GetWindowDrawList(ctx)
    RPR.ImGui_DrawList_AddRectFilled(dl, fx0, fy0, fx0 + combo_w, fy0 + frame_h,
        f_hov and P.frame_hover or P.frame, frame_h / 2)
    RPR.ImGui_DrawList_AddText(dl, fx0 + 14 * S, fy0 + (frame_h - line_h) / 2,
        format == "all" and P.text or P.accent, fmt_label)
    DrawChevron(dl, fx0 + combo_w - 16 * S, fy0 + frame_h / 2, 4 * S, "down", P.muted)
    HoverTip(ctx, "Type filter  (click a label in the list to set it)")
    if RPR.ImGui_IsPopupOpen(ctx, POPUP_FORMAT) then
        RPR.ImGui_SetNextWindowPos(ctx, fx0, fy0 + frame_h + 2 * S, RPR.ImGui_Cond_Always())
    end
    if BeginStyledPopup(ctx, POPUP_FORMAT) then
        for _, f in ipairs(FORMATS) do
            if RPR.ImGui_Selectable(ctx, f.label, f.id == format, 0, math.max(combo_w - 24 * S, widest + 20 * S), 0) then
                SetFormat(f.id)
            end
        end
        EndStyledPopup(ctx)
    end

    -- 2) 검색 입력: 남은 너비를 끝까지 채우고, 지우기(✕)는 입력창 안쪽 오른쪽에 겹쳐 그린다
    RPR.ImGui_SameLine(ctx, 0, gap)
    local input_w = math.max(120, avail_w - combo_w - gap)

    local win_focused = RPR.ImGui_IsWindowFocused(ctx, RPR.ImGui_FocusedFlags_RootAndChildWindows())
    if focus_search or (win_focused and not AnyPopupOpen(ctx)
        and not RPR.ImGui_IsAnyItemActive(ctx)
        and not RPR.ImGui_IsMouseDown(ctx, 0)
        and not drag.entries and not marquee.active) then
        RPR.ImGui_SetKeyboardFocusHere(ctx)
        focus_search = false
    end

    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_FramePadding(), line_h + 22 * S, pad_y)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_FrameRounding(), frame_h / 2)
    RPR.ImGui_SetNextItemWidth(ctx, input_w)
    if RPR.ImGui_SetNextItemAllowOverlap then RPR.ImGui_SetNextItemAllowOverlap(ctx) end
    local x0, y0 = RPR.ImGui_GetCursorScreenPos(ctx)
    local changed, new_q = RPR.ImGui_InputTextWithHint(ctx, "##jkk_search_query",
        MB and "Search FX, actions, tracks, items...    ( !UCS  @folder  " .. MBKeyLabel() .. " → Media Browser )"
            or "Search FX, instruments, actions, tracks, items...", query,
        RPR.ImGui_InputTextFlags_EscapeClearsAll())
    RPR.ImGui_PopStyleVar(ctx, 2)
    if changed then
        query = new_q
        if query ~= "" and not expanded and Store.Get("auto_expand") then SetExpanded(true, false) end
    end
    DrawIcon(ctx, RPR.ImGui_GetWindowDrawList(ctx), "search", x0 + 11 * S, y0 + (frame_h - line_h) / 2, line_h, P.muted, 0)

    if query ~= "" then
        -- 같은 줄에 겹쳐 그려서 줄 높이/간격이 변하지 않게 (검색 시작 시 아래 여백이 생기지 않음)
        RPR.ImGui_SameLine(ctx, 0, 0)
        RPR.ImGui_SetCursorScreenPos(ctx, x0 + input_w - frame_h - 2 * S, y0)
        if DrawnIconButton(ctx, P, "##jkk_search_clear", frame_h, false, "Clear (Esc)", "clear") then
            query = ""
            focus_search = true
        end
    end

    RPR.ImGui_PopStyleVar(ctx, 1)
    Theme.PopFont(ctx)

    -- 접힌 상태 높이: 검색줄 아래 여백 = 구분선과 검색줄 사이 여백(ItemSpacing)
    local h = math.ceil(y0 + frame_h - select(2, RPR.ImGui_GetWindowPos(ctx)) + sp_y)
    if not collapsed_h or math.abs(h - collapsed_h) >= 1 then
        collapsed_h = h
        if math.abs(h - (Store.Get("collapsed_h") or 0)) >= 1 then Store.Set("collapsed_h", h) end
    end
end

----------------------------------------------------------
-- 결과 목록 레이아웃 (RECENT / RESULTS 섹션 머리글 포함)
----------------------------------------------------------
local layout = { row_h = 20, head_h = 0, rc = 0, second = false, n = 0 }

local function BuildLayout(row_h, head_h)
    local n = #results
    local rc = math.min(recent_count, n)
    layout.row_h, layout.head_h, layout.n = row_h, head_h, n
    layout.rc = rc
    layout.second = rc > 0 and rc < n
end

local function RowTop(i)
    local L = layout
    if L.rc == 0 then return (i - 1) * L.row_h end
    if i <= L.rc then return L.head_h + (i - 1) * L.row_h end
    return L.head_h + L.rc * L.row_h + (L.second and L.head_h or 0) + (i - L.rc - 1) * L.row_h
end

local function RowAt(y)
    local L = layout
    if L.rc == 0 then return math.floor(y / L.row_h) + 1 end
    local yy = y - L.head_h
    if yy < L.rc * L.row_h then return math.max(1, math.floor(yy / L.row_h) + 1) end
    yy = yy - L.rc * L.row_h - (L.second and L.head_h or 0)
    return L.rc + math.floor(math.max(0, yy) / L.row_h) + 1
end

local function TotalHeight()
    return RowTop(layout.n + 1)
end

----------------------------------------------------------
-- 키보드
----------------------------------------------------------
local function HandleKeys(ctx, query_before, rows_per_page)
    local close = false
    if AnyPopupOpen(ctx) then
        if Pressed(ctx, RPR.ImGui_Key_Escape(), false) then esc_close_popup = true end
        return false
    end
    if not RPR.ImGui_IsWindowFocused(ctx, RPR.ImGui_FocusedFlags_RootAndChildWindows()) then return false end

    local ctrl, shift = IsCtrlDown(ctx), IsShiftDown(ctx)
    local n = #results
    if n > 0 then
        local prev = sel
        local moved = false
        if Pressed(ctx, RPR.ImGui_Key_DownArrow()) then sel = math.min(n, sel + 1); moved = true end
        if Pressed(ctx, RPR.ImGui_Key_UpArrow()) then sel = math.max(1, sel - 1); moved = true end
        if Pressed(ctx, RPR.ImGui_Key_PageDown()) then sel = math.min(n, sel + rows_per_page); moved = true end
        if Pressed(ctx, RPR.ImGui_Key_PageUp()) then sel = math.max(1, sel - rows_per_page); moved = true end
        if moved then
            if shift then
                -- Shift + 방향키: 기준 행부터 범위 선택
                if msel_count == 0 then anchor = prev end
                SelectRange(anchor, sel, false)
            else
                ClearMulti()
                anchor = sel
            end
            scroll_to_sel = true
            if not expanded then SetExpanded(true, false) end
        end

        if ctrl and Pressed(ctx, RPR.ImGui_Key_D(), false) and results[sel] then
            for _, e in ipairs(EntriesFor(results[sel])) do Store.ToggleFavorite(e.key) end
        end
    end

    -- Enter
    --  * MediaBrowser 단축키(기본 Shift+Enter): JKK MediaBrowser 현재 탭에서 검색
    --  * ! / @ 모드: 선택한 UCS / 폴더를 MediaBrowser에서 검색
    --  * 그 외: 선택 항목 실행 (Shift/Ctrl 중 MediaBrowser 키가 아닌 쪽 = 창 유지 반대 동작)
    if Pressed(ctx, RPR.ImGui_Key_Enter(), false) or Pressed(ctx, RPR.ImGui_Key_KeypadEnter(), false) then
        local alt = IsAltDown(ctx)
        local cur = results[sel]
        if MB and MBKeyMatches(ctrl, shift, alt) then
            RequestMB((cur and cur.mb) and cur or nil, false)
        elseif mb_mode then
            RequestMB(cur, shift or ctrl)
        elseif n > 0 then
            local list = (msel_count > 0) and SelectedEntries() or { cur }
            RequestRun(list, nil, shift or ctrl)
        end
    end

    -- 글자 크기: Ctrl + = / Ctrl + - / Ctrl + 0 (1px 단위)
    if ctrl then
        if Pressed(ctx, RPR.ImGui_Key_Equal(), false) or Pressed(ctx, RPR.ImGui_Key_KeypadAdd(), false) then
            UI.SetFontSize(CurrentFontSize() + 1)
        elseif Pressed(ctx, RPR.ImGui_Key_Minus(), false) or Pressed(ctx, RPR.ImGui_Key_KeypadSubtract(), false) then
            UI.SetFontSize(CurrentFontSize() - 1)
        elseif Pressed(ctx, RPR.ImGui_Key_0(), false) then
            UI.SetFontSize(BaseFontSize())
        end
    end

    if Pressed(ctx, RPR.ImGui_Key_Escape(), false) then
        if msel_count > 0 then
            ClearMulti()
        elseif query_before == "" then
            close = true
        elseif query ~= "" then
            query = ""
            focus_search = true
        end
    end
    return close
end

----------------------------------------------------------
-- 결과 행
----------------------------------------------------------
local function ActionShortcut(e)
    if e.shortcut ~= nil then return e.shortcut or nil end
    e.shortcut = false
    if RPR.CountActionShortcuts and RPR.GetActionShortcutDesc and RPR.SectionFromUniqueID then
        local section = RPR.SectionFromUniqueID(0)
        local cmd = e.named and RPR.NamedCommandLookup(e.named) or e.cmd
        if section and cmd and cmd ~= 0 then
            local ok, cnt = pcall(RPR.CountActionShortcuts, section, cmd)
            if ok and cnt and cnt > 0 then
                local ok2, has, desc = pcall(RPR.GetActionShortcutDesc, section, cmd, 0, "")
                if ok2 and has and desc and desc ~= "" then e.shortcut = desc end
            end
        end
    end
    return e.shortcut or nil
end

local function ActionIsOn(e)
    local cmd = e.named and RPR.NamedCommandLookup(e.named) or e.cmd
    if not cmd or cmd == 0 then return false end
    return RPR.GetToggleCommandStateEx(0, cmd) == 1
end

local function BadgeColumnW(ctx)
    if badge_col.scale ~= S then
        Theme.PushFont(ctx, S * 0.78, "base")
        local w = 0
        for _, b in ipairs(BADGE_SAMPLES) do w = math.max(w, TextW(ctx, b)) end
        Theme.PopFont(ctx)
        badge_col = { scale = S, w = math.ceil(w + 14 * S) }
    end
    return badge_col.w
end

local function DrawBadge(ctx, dl, P, x, y_mid, w, text, fill, hovered)
    Theme.PushFont(ctx, S * 0.78, "base")
    local tw, th = RPR.ImGui_CalcTextSize(ctx, text)
    if not w then w = tw + 12 * S end
    local h = th + 6 * S
    local y1 = y_mid - h / 2
    if fill then
        RPR.ImGui_DrawList_AddRectFilled(dl, x, y1, x + w, y1 + h, fill, 4 * S)
        RPR.ImGui_DrawList_AddText(dl, x + (w - tw) / 2, y1 + 3 * S, P.base, text)
    else
        RPR.ImGui_DrawList_AddRect(dl, x, y1, x + w, y1 + h, hovered and P.badge_hover or P.badge_line, 4 * S, 0, 1)
        RPR.ImGui_DrawList_AddText(dl, x + (w - tw) / 2, y1 + 3 * S, hovered and P.text or P.badge_text, text)
    end
    Theme.PopFont(ctx)
    return w
end

-- 마키(드래그 박스) 선택 시작: ♥/배지 열 또는 목록의 빈 곳에서
local function BeginMarquee(ctx, from_void)
    local wx, wy = RPR.ImGui_GetWindowPos(ctx)
    local mx, my = RPR.ImGui_GetMousePos(ctx)
    marquee.pending, marquee.active, marquee.moved = true, false, false
    marquee.sx, marquee.sy = mx - wx, my - wy + RPR.ImGui_GetScrollY(ctx)
    marquee.from_void = from_void
    marquee.base = nil
    if IsCtrlDown(ctx) or IsShiftDown(ctx) then
        marquee.base = {}
        for e in pairs(msel) do marquee.base[e] = true end
    end
end

local function DrawRow(ctx, P, i, e, row_h, width, child_hovered, detailed)
    local dl = RPR.ImGui_GetWindowDrawList(ctx)
    local x, y = RPR.ImGui_GetCursorScreenPos(ctx)
    local line_h = RPR.ImGui_GetTextLineHeight(ctx)
    local icon_w = math.floor(math.min(row_h, line_h * 2.0) * 0.95)
    local y_mid = y + row_h / 2
    local busy = drag.entries or marquee.active
    local hovered = child_hovered and not busy
        and RPR.ImGui_IsMouseHoveringRect(ctx, x, y, x + width, y + row_h, true)
    local is_multi = msel[e] == true
    local is_cursor = (i == sel)

    -- 배경
    if is_multi then
        RPR.ImGui_DrawList_AddRectFilled(dl, x, y, x + width, y + row_h, P.row_msel)
    elseif is_cursor then
        RPR.ImGui_DrawList_AddRectFilled(dl, x, y, x + width, y + row_h, P.row_sel)
    elseif hovered then
        RPR.ImGui_DrawList_AddRectFilled(dl, x, y, x + width, y + row_h, P.row_hover)
    end
    RPR.ImGui_DrawList_AddLine(dl, x, y + row_h - 0.5, x + width, y + row_h - 0.5, P.row_border, 1)

    local bw = BadgeColumnW(ctx)
    local main_w = math.max(40, width - icon_w * 2 - bw)

    RPR.ImGui_PushID(ctx, tostring(i))
    -- 버튼 배경은 항상 투명: 선택 표시 세로줄이 가려지지 않게
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Button(), 0x00000000)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonHovered(), 0x00000000)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonActive(), 0x00000000)

    -- 1) 즐겨찾기 (이름 왼쪽)
    local fav = Store.IsFavorite(e.key)
    local fav_x = RPR.ImGui_GetCursorScreenPos(ctx)
    local fav_hov = child_hovered and not busy and RPR.ImGui_IsMouseHoveringRect(ctx, fav_x, y, fav_x + icon_w, y + row_h, true)
    local fav_clicked
    if e.mb then
        -- MediaBrowser 제안 행(@폴더 / !UCS)은 즐겨찾기 대상이 아님: 빈 자리만 유지
        fav_clicked = RPR.ImGui_InvisibleButton(ctx, "##fav", icon_w, row_h)
        fav_clicked = false
    else
        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), fav and P.fav or (fav_hov and P.text or P.faint))
        fav_clicked = RPR.ImGui_Button(ctx, (fav and "♥" or "♡") .. "##fav", icon_w, row_h)
        RPR.ImGui_PopStyleColor(ctx, 1)
    end
    if RPR.ImGui_IsItemActivated(ctx) then BeginMarquee(ctx, false) end
    if fav_clicked and not marquee.moved then Store.ToggleFavorite(e.key) end

    -- 2) 배지 (클릭 = 타입 필터)
    RPR.ImGui_SameLine(ctx, 0, 0)
    local bx = x + icon_w
    local badge_clicked = RPR.ImGui_InvisibleButton(ctx, "##badge", bw, row_h)
    local badge_hov = RPR.ImGui_IsItemHovered(ctx) and not busy
    if badge_hov then RPR.ImGui_SetMouseCursor(ctx, RPR.ImGui_MouseCursor_Hand()) end
    if RPR.ImGui_IsItemActivated(ctx) then BeginMarquee(ctx, false) end

    -- 3) 행 본체 (클릭 = 실행 / Ctrl·Shift = 다중 선택 / 드래그 = 드롭)
    RPR.ImGui_SameLine(ctx, 0, 0)
    local clicked = RPR.ImGui_InvisibleButton(ctx, "##row", main_w, row_h)
    if RPR.ImGui_IsItemClicked(ctx, 1) then
        if not msel[e] then ClearMulti() end
        sel = i
        menu_entry = e
        open_menu_req = true
    end
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_WindowPadding(), 12 * S, 9 * S)
    if not e.mb and RPR.ImGui_BeginDragDropSource(ctx, 0) then
        if not drag.entries then
            drag.entries = EntriesFor(e)
            drag_consumed = true
            sel = i
        end
        RPR.ImGui_SetDragDropPayload(ctx, DRAG_TYPE, tostring(#drag.entries))
        local first = drag.entries[1]
        if #drag.entries > 1 then
            RPR.ImGui_Text(ctx, string.format("%d items  (%s, ...)", #drag.entries, first.name))
        else
            RPR.ImGui_Text(ctx, first.name .. "   [" .. first.badge .. "]")
        end
        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), drag.target and P.important or P.muted)
        RPR.ImGui_Text(ctx, drag.label or "Drop on a track/item in REAPER, or on a tag")
        RPR.ImGui_PopStyleColor(ctx, 1)
        RPR.ImGui_EndDragDropSource(ctx)
    end
    RPR.ImGui_PopStyleVar(ctx, 1)

    -- 4) 메뉴
    RPR.ImGui_SameLine(ctx, 0, 0)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), P.faint)
    if RPR.ImGui_Button(ctx, "⋮##menu", icon_w, row_h) then
        if not msel[e] then ClearMulti() end
        sel = i
        menu_entry = e
        open_menu_req = true
    end
    RPR.ImGui_PopStyleColor(ctx, 4)
    RPR.ImGui_PopID(ctx)

    -- 선택 표시 세로줄 (버튼보다 나중에 그려 항상 보이게)
    if is_cursor or is_multi then
        RPR.ImGui_DrawList_AddRectFilled(dl, x, y, x + 3 * S, y + row_h, P.accent)
    end

    -- 내용
    DrawBadge(ctx, dl, P, bx + 2 * S, y_mid, bw - 4 * S, e.badge, nil, badge_hov)
    local left = bx + bw + 10 * S
    if e.color then
        RPR.ImGui_DrawList_AddRectFilled(dl, left, y_mid - 5 * S, left + 10 * S, y_mid + 5 * S, e.color, 2 * S)
        left = left + 18 * S
    end

    local right = x + width - icon_w - 8 * S
    if e.kind == "action" and ActionIsOn(e) then
        Theme.PushFont(ctx, S * 0.78, "base")
        local ow = TextW(ctx, "ON") + 12 * S
        Theme.PopFont(ctx)
        DrawBadge(ctx, dl, P, right - ow, y_mid, ow, "ON", P.accent)
        right = right - ow - 8 * S
    end
    if Library and Library.IsNew(e.key) then
        Theme.PushFont(ctx, S * 0.78, "base")
        local nw = TextW(ctx, "NEW") + 12 * S
        Theme.PopFont(ctx)
        DrawBadge(ctx, dl, P, right - nw, y_mid, nw, "NEW", P.important)
        right = right - nw - 8 * S
    end

    local detail = e.detail
    if e.kind == "action" and detail == "" then detail = ActionShortcut(e) or "" end
    local dev_clickable = (e.kind == "fx" and e.vendor and e.vendor ~= "")
    local dev_rect = nil

    local name_y, detail_y, detail_x, detail_max
    if detailed then
        name_y = y_mid - line_h - 1 * S
        detail_y = y_mid + 2 * S
        detail_x, detail_max = left, right - left
    else
        name_y = y + (row_h - line_h) / 2
        detail_y = name_y
        detail_max = math.max(0, math.min(TextW(ctx, detail), (right - left) * 0.38))
    end

    if detail ~= "" then
        local shown = FitText(ctx, detail, detail_max)
        if shown ~= "" then
            local dw = TextW(ctx, shown)
            if not detailed then
                detail_x = right - dw
                right = right - dw - 14 * S
            end
            local dcol = P.muted
            if dev_clickable then
                dev_rect = { detail_x, detail_y, detail_x + dw, detail_y + line_h }
                if hovered and MouseIn(ctx, dev_rect[1], dev_rect[2], dev_rect[3], dev_rect[4]) then
                    dcol = P.text
                    RPR.ImGui_DrawList_AddLine(dl, detail_x, detail_y + line_h, detail_x + dw, detail_y + line_h, dcol, 1)
                    RPR.ImGui_SetMouseCursor(ctx, RPR.ImGui_MouseCursor_Hand())
                end
            end
            RPR.ImGui_DrawList_AddText(dl, detail_x, detail_y, dcol, shown)
        end
    end

    -- 이름: 즐겨찾기 항목은 강조(Important) 텍스트 색
    DrawHighlighted(ctx, dl, left, name_y, e.name, Query.Highlight(e.lname),
        fav and P.important or P.text, P.hl, right - left)

    -- 클릭 처리
    if badge_clicked and not marquee.moved then
        local f = FilterForEntry(e)
        if f then SetFormat(format == f and "all" or f) end
    elseif clicked and not drag_consumed then
        local ctrl, shift = IsCtrlDown(ctx), IsShiftDown(ctx)
        if ctrl and not shift then
            if msel_count == 0 and sel ~= i and results[sel] then SetMulti(results[sel], true) end
            SetMulti(e, not msel[e])
            sel, anchor = i, i
        elseif shift then
            SelectRange(anchor, i, ctrl)
            sel = i
        elseif dev_rect and MouseIn(ctx, dev_rect[1], dev_rect[2] - 2, dev_rect[3], dev_rect[4] + 2) then
            FocusDeveloper(e.vendor)
        else
            ClearMulti()
            sel, anchor = i, i
            RequestRun({ e }, nil, IsAltDown(ctx))
        end
    end
end

local function DrawSectionHeader(ctx, P, y_local, w, h, label)
    local dl = RPR.ImGui_GetWindowDrawList(ctx)
    local sx, sy = RPR.ImGui_GetWindowPos(ctx)
    local top = sy + y_local - RPR.ImGui_GetScrollY(ctx)
    RPR.ImGui_DrawList_AddRectFilled(dl, sx, top, sx + w, top + h, P.header_bg)
    Theme.PushFont(ctx, S * 0.82, "base")
    local th = RPR.ImGui_GetTextLineHeight(ctx)
    RPR.ImGui_DrawList_AddText(dl, sx + 14 * S, top + (h - th) / 2, P.muted, label)
    Theme.PopFont(ctx)
    RPR.ImGui_DrawList_AddLine(dl, sx, top + h - 0.5, sx + w, top + h - 0.5, P.row_border, 1)
end

-- 마키 진행 (결과 목록 차일드 안에서 호출)
local function UpdateMarquee(ctx, P, inner_w, view_h)
    if not marquee.pending then return end
    local wx, wy = RPR.ImGui_GetWindowPos(ctx)
    local scroll_y = RPR.ImGui_GetScrollY(ctx)
    local mx, my = RPR.ImGui_GetMousePos(ctx)

    if RPR.ImGui_IsMouseDown(ctx, 0) then
        if not marquee.active and RPR.ImGui_IsMouseDragging(ctx, 0, 4 * S) then
            marquee.active, marquee.moved = true, true
        end
        if marquee.active then
            -- 가장자리 자동 스크롤
            local edge = 24 * S
            if my < wy + edge then RPR.ImGui_SetScrollY(ctx, math.max(0, scroll_y - 12 * S))
            elseif my > wy + view_h - edge then RPR.ImGui_SetScrollY(ctx, scroll_y + 12 * S) end

            local cy = my - wy + scroll_y
            local y1, y2 = math.min(marquee.sy, cy), math.max(marquee.sy, cy)
            ClearMulti()
            if marquee.base then for e in pairs(marquee.base) do SetMulti(e, true) end end
            local n = #results
            if n > 0 and y2 > 0 then
                local a = math.max(1, RowAt(math.max(0, y1)))
                local b = math.min(n, RowAt(y2))
                for i = a, b do
                    local top = RowTop(i)
                    if top + layout.row_h > y1 and top < y2 then SetMulti(results[i], true) end
                end
                sel = math.max(1, math.min(n, RowAt(math.max(0, cy))))
            end
            -- 박스 그리기 (화면 좌표)
            local x1 = wx + math.min(marquee.sx, mx - wx)
            local x2 = wx + math.max(marquee.sx, mx - wx)
            local dl = RPR.ImGui_GetWindowDrawList(ctx)
            local sy1, sy2 = wy + y1 - scroll_y, wy + y2 - scroll_y
            RPR.ImGui_DrawList_AddRectFilled(dl, x1, sy1, x2, sy2, WithAlpha(P.accent, 0x30))
            RPR.ImGui_DrawList_AddRect(dl, x1, sy1, x2, sy2, WithAlpha(P.accent, 0xB0), 0, 0, 1)
        end
    else
        if not marquee.moved and marquee.from_void then ClearMulti() end
        marquee.pending, marquee.active = false, false
        if msel_count > 0 then anchor = sel end
    end
end

local function DrawResults(ctx, P, w, h)
    local detailed = Store.Get("view_mode") == "detailed"
    local line_h = RPR.ImGui_GetTextLineHeight(ctx)
    local row_h = math.floor(line_h * (detailed and 3.1 or 2.0) + 0.5)
    local head_h = math.floor(line_h * 1.5 + 0.5)
    local rows_per_page = math.max(1, math.floor(h / row_h) - 1)
    local inner_w = math.floor(w - ScrollbarW(ctx))
    BuildLayout(row_h, head_h)

    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ChildBg(), P.list_bg)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_WindowPadding(), 0, 0)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ItemSpacing(), 0, 0)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_GrabMinSize(), 48 * S)
    local child_visible = RPR.ImGui_BeginChild(ctx, "##jkk_search_results", w, h, 0, 0)
    if child_visible then
        local n = #results
        local child_hovered = RPR.ImGui_IsWindowHovered(ctx)
        local view_h = RPR.ImGui_GetWindowHeight(ctx)
        if n == 0 then
            local msg
            if mb_mode == "folder" and MB and MB.FolderCount() == 0 then
                msg = "No @ folders yet. Open JKK MediaBrowser once to share its folder list."
            elseif mb_mode then
                msg = "No match.  " .. MBKeyLabel() .. " still searches \"" .. query .. "\" in Media Browser"
            elseif Index.building and query ~= "" then msg = "Indexing... results will appear shortly"
            elseif query ~= "" then msg = "No results for \"" .. query .. "\"" ..
                (MB and ("   ·   " .. MBKeyLabel() .. " → Media Browser") or "")
            elseif scope:match("^tag:") then msg = "Empty tag. Drag results onto it in the side panel."
            else msg = "Nothing here yet" end
            local tw = TextW(ctx, msg)
            RPR.ImGui_SetCursorPos(ctx, math.max(8, (inner_w - tw) / 2), 24 * S)
            RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), P.muted)
            RPR.ImGui_Text(ctx, msg)
            RPR.ImGui_PopStyleColor(ctx, 1)
        else
            local scroll_y = RPR.ImGui_GetScrollY(ctx)
            if scroll_to_top then
                scroll_y = 0
                RPR.ImGui_SetScrollY(ctx, 0)
                scroll_to_top = false
            end
            if scroll_to_sel then
                local top = RowTop(sel)
                if sel == 1 or sel == layout.rc + 1 then top = top - head_h end
                local bottom = RowTop(sel) + row_h
                if top < scroll_y then scroll_y = math.max(0, top); RPR.ImGui_SetScrollY(ctx, scroll_y)
                elseif bottom > scroll_y + view_h then scroll_y = bottom - view_h; RPR.ImGui_SetScrollY(ctx, scroll_y) end
                scroll_to_sel = false
            end

            if layout.rc > 0 then
                DrawSectionHeader(ctx, P, 0, inner_w, head_h, "RECENT")
                if layout.second then
                    DrawSectionHeader(ctx, P, head_h + layout.rc * row_h, inner_w, head_h,
                        query ~= "" and "RESULTS" or "ALL")
                end
            end

            local first = math.max(1, RowAt(scroll_y))
            local last = math.min(n, RowAt(scroll_y + view_h) + 1)
            for i = first, last do
                RPR.ImGui_SetCursorPos(ctx, 0, RowTop(i))
                DrawRow(ctx, P, i, results[i], row_h, inner_w, child_hovered, detailed)
            end
            RPR.ImGui_SetCursorPos(ctx, 0, TotalHeight())
            RPR.ImGui_Dummy(ctx, 1, 0)
        end

        -- 빈 곳 클릭/드래그 = 마키 선택 (빈 곳 클릭은 선택 해제)
        if child_hovered and RPR.ImGui_IsMouseClicked(ctx, 0)
            and not RPR.ImGui_IsAnyItemHovered(ctx) and not marquee.pending then
            BeginMarquee(ctx, true)
        end
        UpdateMarquee(ctx, P, inner_w, view_h)
    end
    RPR.ImGui_EndChild(ctx)
    RPR.ImGui_PopStyleVar(ctx, 3)
    RPR.ImGui_PopStyleColor(ctx, 1)
    return rows_per_page
end

----------------------------------------------------------
-- 사이드 패널 (직접 그린 트리: ImGui TreeNode / TreePush 를 사용하지 않음)
----------------------------------------------------------
local SB = { right = 0, tall_h = 24, leaf_h = 20, isz = 16, icon_text_x = 30 }

-- 행 왼쪽 아이콘: Icons/JKK_Search/<Icon_xxx>.png 가 있으면 이미지,
-- 없으면 선택할 수 없는 버튼 모양의 자리표시자
local function DrawIconSlot(ctx, dl, P, key, x, y_mid, size, selected)
    local y1 = y_mid - size / 2
    if GetIcon(ctx, key) then
        DrawIcon(ctx, dl, key, x, y1, size, selected and P.accent or P.text, 0)
        return
    end
    RPR.ImGui_DrawList_AddRectFilled(dl, x, y1, x + size, y1 + size, P.icon_bg, 4 * S)
    RPR.ImGui_DrawList_AddRect(dl, x, y1, x + size, y1 + size, selected and P.accent or P.icon_line, 4 * S, 0, 1)
end

-- icon: "slot"(아이콘 자리) | "dot" | nil
-- chevron: nil | "open" | "closed" (오른쪽)
-- 반환: 클릭 여부, 화살표 영역 클릭 여부
local function SideRow(ctx, P, id, label, selected, opts)
    opts = opts or {}
    local x = (RPR.ImGui_GetCursorScreenPos(ctx))
    local w = math.max(20, SB.right - x)
    local h = opts.tall and SB.tall_h or SB.leaf_h
    RPR.ImGui_PushID(ctx, id)
    local clicked = RPR.ImGui_Selectable(ctx, "##side", selected, 0, w, h)
    RPR.ImGui_PopID(ctx)
    local x1, y1 = RPR.ImGui_GetItemRectMin(ctx)
    local x2, y2 = RPR.ImGui_GetItemRectMax(ctx)
    local dl = RPR.ImGui_GetWindowDrawList(ctx)
    local th = RPR.ImGui_GetTextLineHeight(ctx)
    local y_mid = (y1 + y2) / 2
    local col = selected and P.accent or (opts.muted and P.muted or P.text)

    local tx = x1 + 4 * S
    if opts.icon == "slot" then
        DrawIconSlot(ctx, dl, P, opts.icon_key or id, x1 + 6 * S, y_mid, SB.isz, selected)
        tx = x1 + SB.icon_text_x
    elseif opts.icon == "dot" then
        local isz = math.floor(SB.isz * 0.8)
        if GetIcon(ctx, "tag") then
            DrawIcon(ctx, dl, "tag", x1 + 6 * S + (SB.isz - isz) / 2, y_mid - isz / 2, isz,
                selected and P.accent or P.muted, 0)
        else
            RPR.ImGui_DrawList_AddCircleFilled(dl, x1 + 6 * S + SB.isz / 2, y_mid, 3 * S, selected and P.accent or P.muted)
        end
        tx = x1 + SB.icon_text_x
    end
    local chev_w = opts.chevron and 22 * S or 0
    local right_text_w = opts.right_text and (TextW(ctx, opts.right_text) + 8 * S) or 0
    RPR.ImGui_DrawList_AddText(dl, tx, y_mid - th / 2, col, FitText(ctx, label, x2 - tx - 6 * S - chev_w - right_text_w))
    if opts.right_text then
        RPR.ImGui_DrawList_AddText(dl, x2 - chev_w - right_text_w, y_mid - th / 2, P.important, opts.right_text)
    end

    local chev_clicked = false
    if opts.chevron then
        DrawChevron(dl, x2 - 11 * S, y_mid, 3.5 * S, opts.chevron == "open" and "down" or "right", P.muted)
        if clicked then
            local mx = RPR.ImGui_GetMousePos(ctx)
            chev_clicked = mx >= x2 - chev_w - 4 * S
        end
    end
    if sidebar_scroll_to == id then
        RPR.ImGui_SetScrollHereY(ctx, 0.35)
        sidebar_scroll_to = nil
    end
    return clicked, chev_clicked
end

-- 대분류 머리글 (BROWSE / PROJECT / TAGS): 왼쪽 화살표 + 흐린 글씨, 클릭 = 접기/펼치기
-- plus_tip 이 있으면 오른쪽에 + 버튼 (반환 두 번째 값 = + 클릭)
local function SectionRow(ctx, P, key, label, plus_tip)
    local x = (RPR.ImGui_GetCursorScreenPos(ctx))
    local h = SB.leaf_h
    local plus_w = plus_tip and h or 0
    local w = math.max(20, SB.right - x - plus_w)
    RPR.ImGui_PushID(ctx, "sec_" .. key)
    if RPR.ImGui_Selectable(ctx, "##sec", false, 0, w, h) then tree_open[key] = not tree_open[key] end
    local x1, y1 = RPR.ImGui_GetItemRectMin(ctx)
    local _, y2 = RPR.ImGui_GetItemRectMax(ctx)
    local dl = RPR.ImGui_GetWindowDrawList(ctx)
    local th = RPR.ImGui_GetTextLineHeight(ctx)
    DrawChevron(dl, x1 + 8 * S, (y1 + y2) / 2, 3.5 * S, tree_open[key] and "down" or "right", P.muted)
    RPR.ImGui_DrawList_AddText(dl, x1 + 20 * S, (y1 + y2) / 2 - th / 2, P.muted, label)
    local plus_clicked = false
    if plus_tip then
        RPR.ImGui_SameLine(ctx, 0, 0)
        plus_clicked = DrawnIconButton(ctx, P, "##plus", plus_w, false, plus_tip, "plus")
    end
    RPR.ImGui_PopID(ctx)
    return tree_open[key], plus_clicked
end

local function NavItem(ctx, P, label, id, opts)
    opts = opts or { tall = true, icon = "slot" }
    local clicked = SideRow(ctx, P, id, label, scope == id, opts)
    if clicked then SetScope(id) end
    return clicked
end

-- 드래그 중인 결과를 이 사이드 패널 항목에 놓을 수 있게
local function DropTarget(ctx, on_drop)
    if not drag.entries then return end
    if RPR.ImGui_BeginDragDropTarget(ctx) then
        if RPR.ImGui_AcceptDragDropPayload(ctx, DRAG_TYPE) and drag.entries then
            on_drop(drag.entries)
            drag.entries, drag.target, drag.label = nil, nil, nil
        end
        RPR.ImGui_EndDragDropTarget(ctx)
    end
end

local function GroupRow(ctx, P, key, label, arr, prefix)
    if #arr == 0 then return end
    local child_sel = scope:sub(1, #prefix) == prefix
    if SideRow(ctx, P, "grp_" .. key, label, false,
        { chevron = tree_open[key] and "open" or "closed", right_text = (child_sel and not tree_open[key]) and "•" or nil }) then
        tree_open[key] = not tree_open[key]
    end
    if tree_open[key] then
        RPR.ImGui_Indent(ctx, 12 * S)
        for _, v in ipairs(arr) do NavItem(ctx, P, v.name, prefix .. v.name, {}) end
        RPR.ImGui_Unindent(ctx, 12 * S)
    end
end

local function DrawTargetBox(ctx, P, w, h)
    local e = results[sel]
    local multi = msel_count > 1
    local verb = multi and string.format("Insert %d", msel_count) or Actions.VerbFor(e)
    local is_fx = e and (e.kind == "fx" or e.kind == "chain")
    local sub_text, sub_col, tip = "", P.muted, nil
    if e and e.mb then
        verb = "Search"
        sub_text = "in Media Browser"
        multi = false
    elseif is_fx or multi then
        local t = Actions.ResolveTarget(nil, false)
        if (t.mode == "none" or t.count == 0) then
            if e and e.is_instrument then sub_text = "on New Track"
            else sub_text = "No selection"; sub_col = P.warn end
        else
            sub_text = "on " .. t.label
            tip = t.tooltip
        end
    elseif e then
        sub_text = e.name
    else
        sub_text = "-"
    end

    local dd_w = math.floor(26 * S)
    local main_w = w - dd_w - 4 * S
    local x, y = RPR.ImGui_GetCursorScreenPos(ctx)
    local clicked = RPR.ImGui_InvisibleButton(ctx, "##jkk_search_target_main", main_w, h)
    local hovered = RPR.ImGui_IsItemHovered(ctx)
    local dl = RPR.ImGui_GetWindowDrawList(ctx)
    RPR.ImGui_DrawList_AddRectFilled(dl, x, y, x + main_w, y + h, hovered and P.box_hover or P.box_bg, 8 * S)
    local line_h = RPR.ImGui_GetTextLineHeight(ctx)
    -- 두 줄(제목 글꼴 + 기본 글꼴)을 실제 높이 기준으로 세로 가운데 정렬
    Theme.PushFont(ctx, S, "heading")
    local head_h = RPR.ImGui_GetTextLineHeight(ctx)
    local line_gap = 4 * S
    local ty = y + (h - (head_h + line_gap + line_h)) / 2
    RPR.ImGui_DrawList_AddText(dl, x + 12 * S, ty, P.text, verb)
    Theme.PopFont(ctx)
    RPR.ImGui_DrawList_AddText(dl, x + 12 * S, ty + head_h + line_gap, sub_col, FitText(ctx, sub_text, main_w - 20 * S))
    if e then
        Theme.PushFont(ctx, S * 0.8, "base")
        local kl = multi and "MULTI" or (KIND_LABEL[e.kind] or "")
        RPR.ImGui_DrawList_AddText(dl, x + main_w - TextW(ctx, kl) - 10 * S, y + 6 * S, P.faint, kl)
        Theme.PopFont(ctx)
    end
    HoverTip(ctx, tip)
    if clicked and e then
        RequestRun(multi and SelectedEntries() or { e }, nil, IsAltDown(ctx))
    end

    RPR.ImGui_SameLine(ctx, 0, 4 * S)
    local bx, by = RPR.ImGui_GetCursorScreenPos(ctx)
    if RPR.ImGui_InvisibleButton(ctx, "##jkk_search_target_dd", dd_w, h) then open_target_req = true end
    local dd_hov = RPR.ImGui_IsItemHovered(ctx)
    RPR.ImGui_DrawList_AddRectFilled(dl, bx, by, bx + dd_w, by + h, dd_hov and P.box_hover or P.box_bg, 8 * S)
    DrawChevron(dl, bx + dd_w / 2, by + h / 2, 4 * S, "down", P.muted)
    HoverTip(ctx, "Insert target & options")
end

local function DrawSidebar(ctx, P, w, h)
    local line_h = RPR.ImGui_GetTextLineHeight(ctx)
    local box_h = math.floor(line_h * 2 + 24 * S)
    local _, spacing_y = StyleVec(ctx, RPR.ImGui_StyleVar_ItemSpacing())
    local list_h = math.max(40, h - box_h - spacing_y)
    local pad_x = 8 * S

    SB.tall_h = math.floor(line_h * 1.95 + 0.5)
    SB.leaf_h = math.floor(line_h * 1.6 + 0.5)
    SB.isz = math.floor(SB.tall_h * 0.66)
    SB.icon_text_x = 6 * S + SB.isz + 9 * S

    RPR.ImGui_BeginGroup(ctx)
    local sx = RPR.ImGui_GetCursorScreenPos(ctx)
    SB.right = sx + w - pad_x - ScrollbarW(ctx)

    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ChildBg(), P.sidebar_bg)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Header(), P.row_sel)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_HeaderHovered(), P.row_hover)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_HeaderActive(), P.row_sel)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_WindowPadding(), pad_x, 6 * S)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ItemSpacing(), 4 * S, 1 * S)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_FramePadding(), 4 * S, 4 * S)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_GrabMinSize(), 48 * S)
    local child_visible = RPR.ImGui_BeginChild(ctx, "##jkk_search_sidebar", w, list_h, 0, 0)
    if child_visible then
        -- 최상단 (대분류 없음)
        NavItem(ctx, P, "All Results", "all")
        NavItem(ctx, P, "Recent", "recent")
        NavItem(ctx, P, "Favorites", "favorites")
        DropTarget(ctx, function(list)
            for _, e in ipairs(list) do
                if not Store.IsFavorite(e.key) then Store.ToggleFavorite(e.key) end
            end
            UI.SetStatus(true, string.format("Added %d to favorites", #list))
        end)
        if Library and Library.NewCount() > 0 then
            if NavItem(ctx, P, "New", "new", { tall = true, icon = "slot", right_text = tostring(Library.NewCount()) }) then end
            if RPR.ImGui_IsItemClicked(ctx, 1) then open_new_menu_req = true end
        end

        -- BROWSE
        RPR.ImGui_Dummy(ctx, 0, 4 * S)
        if SectionRow(ctx, P, "browse", "BROWSE") then
            local fx_clicked, fx_chev = SideRow(ctx, P, "effects", "Effects", scope == "effects",
                { tall = true, icon = "slot", chevron = tree_open.effects and "open" or "closed" })
            if fx_chev then tree_open.effects = not tree_open.effects
            elseif fx_clicked then SetScope("effects") end
            if tree_open.effects then
                local indent = SB.icon_text_x - 4 * S
                RPR.ImGui_Indent(ctx, indent)
                GroupRow(ctx, P, "cat", "Category", Index.categories, "cat:")
                GroupRow(ctx, P, "dev", "Developers", Index.developers, "dev:")
                RPR.ImGui_Unindent(ctx, indent)
            end
            NavItem(ctx, P, "Instruments", "instruments")
            NavItem(ctx, P, "FX Chains", "chains")
            NavItem(ctx, P, "Track Templates", "templates")
            NavItem(ctx, P, "Actions", "actions")
        end

        -- PROJECT
        RPR.ImGui_Dummy(ctx, 0, 4 * S)
        if SectionRow(ctx, P, "project", "PROJECT") then
            NavItem(ctx, P, "Tracks", "tracks")
            NavItem(ctx, P, "Items", "items")
            NavItem(ctx, P, "Markers & Regions", "markers")
        end

        -- TAGS (사용자 태그)
        RPR.ImGui_Dummy(ctx, 0, 4 * S)
        local tags_open, plus = SectionRow(ctx, P, "tags", "TAGS",
            msel_count > 0 and string.format("New tag from %d selected", msel_count) or "New tag")
        if plus and Library then
            local keys = (msel_count > 0) and KeysOf(SelectedEntries()) or {}
            local t = Library.AddTag("New Tag", keys)
            tree_open.tags = true
            SetScope("tag:" .. t.id)
            OpenRename(t.id)
        end
        if tags_open and Library then
            local tags = Library.Tags()
            if #tags == 0 then
                RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), P.faint)
                RPR.ImGui_TextWrapped(ctx, "No tags yet. Press + to create one, then drag results onto it.")
                RPR.ImGui_PopStyleColor(ctx, 1)
            end
            for _, t in ipairs(tags) do
                local id = "tag:" .. t.id
                if SideRow(ctx, P, id, t.name, scope == id,
                    { tall = false, icon = "dot", right_text = nil }) then
                    SetScope(id)
                end
                if RPR.ImGui_IsItemClicked(ctx, 1) then
                    tag_menu_id = t.id
                    open_tag_menu_req = true
                end
                if RPR.ImGui_IsItemHovered(ctx) and RPR.ImGui_IsMouseDoubleClicked(ctx, 0) then
                    OpenRename(t.id)
                end
                local tag_id = t.id
                DropTarget(ctx, function(list) AddEntriesToTag(tag_id, list) end)
            end
        end
    end
    RPR.ImGui_EndChild(ctx)
    RPR.ImGui_PopStyleVar(ctx, 4)
    RPR.ImGui_PopStyleColor(ctx, 4)

    DrawTargetBox(ctx, P, w, box_h)
    RPR.ImGui_EndGroup(ctx)
end

-- 사이드 패널(좌)과 결과 목록 사이의 너비 조절 핸들
local function DrawSplitter(ctx, w, h)
    local x, y = RPR.ImGui_GetCursorScreenPos(ctx)
    RPR.ImGui_InvisibleButton(ctx, "##jkk_search_splitter", w, h)
    local hov = RPR.ImGui_IsItemHovered(ctx)
    local act = RPR.ImGui_IsItemActive(ctx)
    if hov or act then RPR.ImGui_SetMouseCursor(ctx, RPR.ImGui_MouseCursor_ResizeEW()) end
    if act then
        local dx = RPR.ImGui_GetMouseDelta(ctx)
        sidebar_w = sidebar_w + (dx or 0)
    end
    if RPR.ImGui_IsItemDeactivated(ctx) then Store.Set("sidebar_w", math.floor(sidebar_w)) end
    local col = Theme.GetSplitterColor and Theme.GetSplitterColor(act, hov) or 0x808080FF
    local cx = x + w / 2
    RPR.ImGui_DrawList_AddLine(RPR.ImGui_GetWindowDrawList(ctx), cx, y + 6 * S, cx, y + h - 6 * S, col,
        (act or hov) and 3 or 1)
end

----------------------------------------------------------
-- 팝업
----------------------------------------------------------
local function Check(ctx, label, key)
    local changed, v = RPR.ImGui_Checkbox(ctx, label, Store.Get(key) and true or false)
    if changed then Store.Set(key, v) end
end

local function Radio(ctx, label, key, value)
    if RPR.ImGui_RadioButton(ctx, label, Store.Get(key) == value) then Store.Set(key, value) end
end

local function SectionLabel(ctx, P, text)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), P.muted)
    RPR.ImGui_Text(ctx, text)
    RPR.ImGui_PopStyleColor(ctx, 1)
end

local function DrawTargetOptions(ctx, P)
    SectionLabel(ctx, P, "Insert FX on")
    for _, m in ipairs(Actions.TARGET_MODES) do
        Radio(ctx, m.label .. "##tm_" .. m.id, "target_mode", m.id)
    end
    RPR.ImGui_Separator(ctx)
    SectionLabel(ctx, P, "Chain position")
    Radio(ctx, "End of chain##pos_end", "insert_pos", "end")
    RPR.ImGui_SameLine(ctx)
    Radio(ctx, "Start of chain##pos_start", "insert_pos", "start")
    RPR.ImGui_Separator(ctx)
    SectionLabel(ctx, P, "After inserting, show")
    Radio(ctx, "Floating window##show_float", "show_fx", "float")
    RPR.ImGui_SameLine(ctx)
    Radio(ctx, "FX chain##show_chain", "show_fx", "chain")
    RPR.ImGui_SameLine(ctx)
    Radio(ctx, "Nothing##show_none", "show_fx", "none")
end

local function DrawSettingsPopup(ctx, P)
    if not BeginStyledPopup(ctx, POPUP_SETTINGS) then return end

    Theme.PushText(ctx, "accent")
    RPR.ImGui_Text(ctx, "JKK Search Settings")
    Theme.PopText(ctx)
    RPR.ImGui_Separator(ctx)

    -- 글자 크기: 정수 px 단위 버튼
    SectionLabel(ctx, P, "Text size  (Ctrl + = / - / 0)")
    local fs = CurrentFontSize()
    local bh = RPR.ImGui_GetFrameHeight(ctx)
    if RPR.ImGui_Button(ctx, "-##font_minus", bh, bh) then UI.SetFontSize(fs - 1) end
    RPR.ImGui_SameLine(ctx, 0, 6 * S)
    RPR.ImGui_AlignTextToFramePadding(ctx)
    local label = string.format("%d px", fs)
    local lw = TextW(ctx, "00 px")
    local cx = RPR.ImGui_GetCursorPosX(ctx)
    RPR.ImGui_SetCursorPosX(ctx, cx + (lw - TextW(ctx, label)) / 2)
    RPR.ImGui_Text(ctx, label)
    RPR.ImGui_SameLine(ctx, 0, 0)
    RPR.ImGui_SetCursorPosX(ctx, cx + lw + 6 * S)
    if RPR.ImGui_Button(ctx, "+##font_plus", bh, bh) then UI.SetFontSize(fs + 1) end
    RPR.ImGui_SameLine(ctx, 0, 10 * S)
    if RPR.ImGui_Button(ctx, string.format("Default (%d)##font_reset", BaseFontSize())) then
        UI.SetFontSize(BaseFontSize())
    end
    RPR.ImGui_Separator(ctx)

    Check(ctx, "Close window after running", "close_after_run")
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), P.faint)
    RPR.ImGui_Text(ctx, "      " .. KeepOpenLabel() .. " or Alt + click does the opposite")
    RPR.ImGui_PopStyleColor(ctx, 1)
    Check(ctx, "Expand results automatically while typing", "auto_expand")
    Check(ctx, "Open window at mouse cursor", "open_at_mouse")
    Check(ctx, "Close window when it loses focus", "close_on_unfocus")
    RPR.ImGui_Separator(ctx)

    DrawTargetOptions(ctx, P)
    Check(ctx, "New instrument tracks: MIDI input + arm + monitor", "arm_instrument_track")
    RPR.ImGui_Separator(ctx)

    -- JKK MediaBrowser 연동 (설치되어 있을 때만 이 항목 자체가 보인다)
    if MB then
        SectionLabel(ctx, P, "JKK MediaBrowser")
        RPR.ImGui_Text(ctx, "Search the current Media Browser tab with:")
        for i, k in ipairs(MB_KEYS) do
            if i > 1 then RPR.ImGui_SameLine(ctx) end
            Radio(ctx, k.label .. "##mbkey_" .. k.id, "mb_key", k.id)
        end
        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), P.faint)
        RPR.ImGui_Text(ctx, "      Locked filter blocks are kept.  !UCS and @folder use Media Browser's engine.")
        RPR.ImGui_Text(ctx, string.format("      @ folders shared by Media Browser: %d", MB.FolderCount()))
        RPR.ImGui_PopStyleColor(ctx, 1)
        RPR.ImGui_Separator(ctx)
    end

    SectionLabel(ctx, P, "Search")
    Check(ctx, "Hide VST2 when a VST3 version exists", "hide_vst2_dupes")
    Check(ctx, "Fuzzy / initials matching (e.g. \"rba\" → RBass)", "fuzzy")
    Check(ctx, "Actions", "search_actions")
    RPR.ImGui_SameLine(ctx)
    Check(ctx, "Tracks", "search_tracks")
    RPR.ImGui_SameLine(ctx)
    Check(ctx, "Items", "search_items")
    RPR.ImGui_SameLine(ctx)
    Check(ctx, "Markers/Regions", "search_markers")
    Check(ctx, "Open projects in a new tab", "project_new_tab")
    RPR.ImGui_Separator(ctx)

    Theme.PushButton(ctx, "primary")
    if RPR.ImGui_Button(ctx, "Refresh") then DoRefresh() end
    RPR.ImGui_SameLine(ctx)
    if RPR.ImGui_Button(ctx, "Clear Recent") then
        Store.ClearRecent()
        UI.SetStatus(true, "Recent list cleared")
    end
    RPR.ImGui_SameLine(ctx)
    if RPR.ImGui_Button(ctx, "Theme...") and Theme.OpenEditor then
        Theme.OpenEditor()
    end
    Theme.PopButton(ctx)
    EndStyledPopup(ctx)
end

local function DrawRowMenu(ctx, P)
    if open_menu_req then
        RPR.ImGui_OpenPopup(ctx, POPUP_ROW_MENU)
        open_menu_req = false
    end
    if not BeginStyledPopup(ctx, POPUP_ROW_MENU) then return end
    local e = menu_entry
    if not e then EndStyledPopup(ctx) return end
    local list = EntriesFor(e)
    local multi = #list > 1

    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), P.muted)
    if multi then
        RPR.ImGui_Text(ctx, string.format("%d selected items", #list))
    else
        RPR.ImGui_Text(ctx, FitText(ctx, e.name, 320 * S) .. "   [" .. e.badge .. "]")
    end
    RPR.ImGui_PopStyleColor(ctx, 1)
    RPR.ImGui_Separator(ctx)

    if e.mb then
        if RPR.ImGui_MenuItem(ctx, "Search in Media Browser", "Enter") then RequestMB(e, false) end
        if RPR.ImGui_MenuItem(ctx, "Search in Media Browser and keep window open", KeepOpenLabel()) then RequestMB(e, true) end
        EndStyledPopup(ctx)
        return
    end

    local has_fx = false
    for _, x in ipairs(list) do if x.kind == "fx" or x.kind == "chain" then has_fx = true end end
    if has_fx then
        local t = Actions.ResolveTarget(nil, false)
        if RPR.ImGui_MenuItem(ctx, "Insert  (" .. t.label .. ")", "Enter") then RequestRun(list, nil, false) end
        if RPR.ImGui_MenuItem(ctx, "Insert and keep window open", KeepOpenLabel()) then RequestRun(list, nil, true) end
        RPR.ImGui_Separator(ctx)
        if RPR.ImGui_MenuItem(ctx, "Insert on selected tracks") then RequestRun(list, { target_mode = "tracks" }, false) end
        if RPR.ImGui_MenuItem(ctx, "Insert on selected items (take FX)") then RequestRun(list, { target_mode = "items" }, false) end
        if RPR.ImGui_MenuItem(ctx, "Insert as track input FX") then RequestRun(list, { target_mode = "input" }, false) end
        if RPR.ImGui_MenuItem(ctx, "Insert on master track") then RequestRun(list, { target_mode = "master" }, false) end
        if RPR.ImGui_MenuItem(ctx, "Insert on new track") then RequestRun(list, { target_mode = "newtrack" }, false) end
    else
        local verb = multi and "Run all" or Actions.VerbFor(e)
        if RPR.ImGui_MenuItem(ctx, verb, "Enter") then RequestRun(list, nil, false) end
        if RPR.ImGui_MenuItem(ctx, verb .. " and keep window open", KeepOpenLabel()) then RequestRun(list, nil, true) end
    end
    if MB and query:match("%S") then
        if RPR.ImGui_MenuItem(ctx, "Search \"" .. FitText(ctx, query, 200 * S) .. "\" in Media Browser", MBKeyLabel()) then
            RequestMB(nil, false)
        end
    end
    RPR.ImGui_Separator(ctx)

    -- 최근 항목에서 삭제 (최근 항목이 하나라도 포함되어 있을 때)
    local recent_in = {}
    for _, x in ipairs(list) do if Store.RecentRank(x.key) then recent_in[#recent_in + 1] = x end end
    if #recent_in > 0 then
        local label = (#recent_in > 1) and string.format("Remove %d from Recent", #recent_in) or "Remove from Recent"
        if RPR.ImGui_MenuItem(ctx, label) then
            for _, x in ipairs(recent_in) do Store.RemoveRecent(x.key) end
            ClearMulti()
            UI.SetStatus(true, label:gsub("^Remove", "Removed"))
        end
        RPR.ImGui_Separator(ctx)
    end

    -- 태그
    if Library then
        if RPR.ImGui_BeginMenu(ctx, "Add to tag") then
            for _, t in ipairs(Library.Tags()) do
                if RPR.ImGui_MenuItem(ctx, t.name .. "##addtag_" .. t.id) then AddEntriesToTag(t.id, list) end
            end
            if #Library.Tags() > 0 then RPR.ImGui_Separator(ctx) end
            if RPR.ImGui_MenuItem(ctx, "New tag...") then
                local t = Library.AddTag("New Tag", KeysOf(list))
                tree_open.tags = true
                OpenRename(t.id)
            end
            RPR.ImGui_EndMenu(ctx)
        end
        local cur_tag = scope:match("^tag:(.*)$")
        if cur_tag and RPR.ImGui_MenuItem(ctx, "Remove from this tag") then
            Library.RemoveFromTag(cur_tag, KeysOf(list))
        end
    end

    local fav = Store.IsFavorite(e.key)
    if RPR.ImGui_MenuItem(ctx, fav and "Remove from favorites" or "Add to favorites", "Ctrl+D") then
        for _, x in ipairs(list) do
            if Store.IsFavorite(x.key) == fav then Store.ToggleFavorite(x.key) end
        end
    end
    if not multi and e.kind == "fx" and e.vendor and e.vendor ~= ""
        and RPR.ImGui_MenuItem(ctx, "Show all from " .. e.vendor) then
        FocusDeveloper(e.vendor)
    end
    if not multi then
        if RPR.ImGui_MenuItem(ctx, "Copy name") then
            RPR.ImGui_SetClipboardText(ctx, e.full_name or e.name)
        end
        if e.kind == "action" and RPR.ImGui_MenuItem(ctx, "Copy command ID") then
            RPR.ImGui_SetClipboardText(ctx, e.named or tostring(e.cmd))
        end
        if (e.kind == "chain" or e.kind == "template" or e.kind == "project") and e.full_path
            and RPR.ImGui_MenuItem(ctx, "Copy file path") then
            RPR.ImGui_SetClipboardText(ctx, e.full_path)
        end
    end
    EndStyledPopup(ctx)
end

local function DrawTargetPopup(ctx, P)
    if open_target_req then
        RPR.ImGui_OpenPopup(ctx, POPUP_TARGET)
        open_target_req = false
    end
    if not BeginStyledPopup(ctx, POPUP_TARGET) then return end
    DrawTargetOptions(ctx, P)
    EndStyledPopup(ctx)
end

-- 태그 우클릭 메뉴 / 이름 바꾸기 / 삭제 확인 / New 메뉴
local function DrawTagPopups(ctx, P)
    if not Library then return end
    if open_tag_menu_req then
        RPR.ImGui_OpenPopup(ctx, POPUP_TAG_MENU)
        open_tag_menu_req = false
    end
    if BeginStyledPopup(ctx, POPUP_TAG_MENU) then
        local t = Library.FindTag(tag_menu_id)
        if t then
            RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), P.muted)
            RPR.ImGui_Text(ctx, string.format("%s  (%d)", FitText(ctx, t.name, 260 * S), #t.keys))
            RPR.ImGui_PopStyleColor(ctx, 1)
            RPR.ImGui_Separator(ctx)
            if RPR.ImGui_MenuItem(ctx, "Rename") then OpenRename(t.id) end
            if RPR.ImGui_MenuItem(ctx, "Duplicate") then
                local c = Library.DuplicateTag(t.id)
                if c then SetScope("tag:" .. c.id) end
            end
            if RPR.ImGui_MenuItem(ctx, "Delete") then delete_tag.id, delete_tag.req = t.id, true end
            RPR.ImGui_Separator(ctx)
            if RPR.ImGui_MenuItem(ctx, "Move up") then Library.MoveTag(t.id, -1) end
            if RPR.ImGui_MenuItem(ctx, "Move down") then Library.MoveTag(t.id, 1) end
        else
            RPR.ImGui_CloseCurrentPopup(ctx)
        end
        EndStyledPopup(ctx)
    end

    if rename.req then
        RPR.ImGui_OpenPopup(ctx, POPUP_TAG_RENAME)
        rename.req = false
    end
    if BeginStyledPopup(ctx, POPUP_TAG_RENAME) then
        SectionLabel(ctx, P, "Tag name")
        if rename.focus then
            RPR.ImGui_SetKeyboardFocusHere(ctx)
            rename.focus = false
        end
        RPR.ImGui_SetNextItemWidth(ctx, 260 * S)
        local enter
        enter, rename.buf = RPR.ImGui_InputText(ctx, "##jkk_tag_rename_input", rename.buf,
            RPR.ImGui_InputTextFlags_EnterReturnsTrue() | RPR.ImGui_InputTextFlags_AutoSelectAll())
        Theme.PushButton(ctx, "confirm")
        local ok = RPR.ImGui_Button(ctx, "OK", 80 * S, 0)
        Theme.PopButton(ctx)
        RPR.ImGui_SameLine(ctx)
        if RPR.ImGui_Button(ctx, "Cancel", 80 * S, 0) then RPR.ImGui_CloseCurrentPopup(ctx) end
        if enter or ok then
            Library.RenameTag(rename.id, rename.buf)
            RPR.ImGui_CloseCurrentPopup(ctx)
            focus_search = true
        end
        EndStyledPopup(ctx)
    end

    if delete_tag.req then
        RPR.ImGui_OpenPopup(ctx, POPUP_TAG_DELETE)
        delete_tag.req = false
    end
    if BeginStyledPopup(ctx, POPUP_TAG_DELETE) then
        local t = Library.FindTag(delete_tag.id)
        if t then
            RPR.ImGui_Text(ctx, string.format("Delete tag \"%s\"?", t.name))
            RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), P.muted)
            RPR.ImGui_Text(ctx, "The FX themselves are not affected.")
            RPR.ImGui_PopStyleColor(ctx, 1)
            Theme.PushButton(ctx, "highlight")
            if RPR.ImGui_Button(ctx, "Delete", 90 * S, 0) then
                if scope == "tag:" .. t.id then SetScope("all") end
                Library.DeleteTag(t.id)
                RPR.ImGui_CloseCurrentPopup(ctx)
            end
            Theme.PopButton(ctx)
            RPR.ImGui_SameLine(ctx)
            if RPR.ImGui_Button(ctx, "Cancel", 90 * S, 0) then RPR.ImGui_CloseCurrentPopup(ctx) end
        else
            RPR.ImGui_CloseCurrentPopup(ctx)
        end
        EndStyledPopup(ctx)
    end

    if open_new_menu_req then
        RPR.ImGui_OpenPopup(ctx, POPUP_NEW_MENU)
        open_new_menu_req = false
    end
    if BeginStyledPopup(ctx, POPUP_NEW_MENU) then
        if RPR.ImGui_MenuItem(ctx, "Clear New list") then
            Library.ClearNew()
            if scope == "new" then SetScope("all") end
        end
        EndStyledPopup(ctx)
    end
end

----------------------------------------------------------
-- 드래그 앤 드롭: REAPER 트랙/아이템 위에서 놓으면 그 대상에 삽입
----------------------------------------------------------
local function UpdateDrag(ctx)
    if drag.entries then
        local down = RPR.ImGui_IsMouseDown(ctx, 0)
        if RPR.JS_Mouse_GetState then down = (RPR.JS_Mouse_GetState(1) & 1) == 1 end

        local wx, wy = RPR.ImGui_GetWindowPos(ctx)
        local ww, wh = RPR.ImGui_GetWindowSize(ctx)
        local mx, my = RPR.ImGui_GetMousePos(ctx)
        local inside = mx >= wx and mx <= wx + ww and my >= wy and my <= wy + wh

        local insertable = {}
        for _, e in ipairs(drag.entries) do if IsInsertable(e) then insertable[#insertable + 1] = e end end

        if inside then
            drag.target, drag.label = nil, "Drop on a tag or Favorites, or drag into REAPER"
        elseif #insertable == 0 then
            drag.target, drag.label = nil, "Only FX, chains and templates can be dropped in REAPER"
        else
            local nx, ny = RPR.GetMousePosition()
            drag.target = Actions.TargetAtPoint(nx, ny, insertable[1])
            drag.label = drag.target and ("Drop on  " .. drag.target.label) or "No track or item here"
        end

        if not down then
            if drag.target and #insertable > 0 then
                RequestRun(insertable, { explicit = drag.target }, IsAltDown(ctx))
            end
            drag.entries, drag.target, drag.label = nil, nil, nil
        end
    end
    if not drag.entries and not RPR.ImGui_IsMouseDown(ctx, 0) then drag_consumed = false end
end

-- 인덱스 구축 완료 시: 태그 초기화(첫 실행), New 갱신
local function OnIndexBuilt()
    if not Library then return end
    if Library.NeedsSeed() then Library.SeedFromFolders(Index.folders) end
    local n = Library.UpdateNew(Index.GetList("fx"))
    if refresh_requested then
        refresh_requested = false
        if n > 0 then
            UI.SetStatus(true, string.format("Found %d new plugin%s", n, n == 1 and "" or "s"))
            SetScope("new")
        else
            UI.SetStatus(true, "Refreshed. No new plugins found")
        end
    end
end

----------------------------------------------------------
-- 메인 그리기 (true 반환 시 창 닫기)
----------------------------------------------------------
function UI.Draw(ctx)
    S = UI.ComputeScale()
    local P = BuildPalette()
    local close = false
    local query_before = query
    local expanded_at_start = expanded
    if esc_close_popup and not AnyPopupOpen(ctx) then esc_close_popup = false end

    if was_building and not Index.building then OnIndexBuilt() end
    was_building = Index.building

    local focused = RPR.ImGui_IsWindowFocused(ctx, RPR.ImGui_FocusedFlags_RootAndChildWindows())
    if Sel and Sel.Update then Sel.Update(focused) end

    local now = RPR.time_precise()
    if focused or drag.entries then
        was_focused, unfocus_since = was_focused or focused, nil
    elseif was_focused and Store.Get("close_on_unfocus") then
        unfocus_since = unfocus_since or now
        if now - unfocus_since > 0.25 then close = true end
    end

    if DrawHeader(ctx, P) then close = true end
    DrawSearchRow(ctx, P)
    UpdateResults()

    local rows_per_page = 8
    -- 펼침/접힘이 이번 프레임에 바뀌었으면 창 크기가 반영되는 다음 프레임부터 본문을 그린다
    local avail_w, avail_h = RPR.ImGui_GetContentRegionAvail(ctx)
    if expanded and expanded_at_start and avail_h >= 80 then
        local body_h = avail_h
        local show_sidebar = Store.Get("show_sidebar") and avail_w > 380 * S
        local split_w = math.floor(8 * S)
        local sw = 0
        if show_sidebar then
            sidebar_w = math.max(150 * S, math.min(avail_w * 0.6, sidebar_w))
            sw = math.floor(sidebar_w)
        end
        local results_w = avail_w - (show_sidebar and (sw + split_w) or 0)
        if show_sidebar then
            DrawSidebar(ctx, P, sw, body_h)
            RPR.ImGui_SameLine(ctx, 0, 0)
            DrawSplitter(ctx, split_w, body_h)
            RPR.ImGui_SameLine(ctx, 0, 0)
        end
        rows_per_page = DrawResults(ctx, P, results_w, body_h)
    end
    -- 목록이 그려지지 않은 프레임에 마우스를 놓아도 마키가 남지 않도록
    if marquee.pending and not RPR.ImGui_IsMouseDown(ctx, 0) then
        marquee.pending, marquee.active = false, false
    end

    UpdateDrag(ctx)
    if HandleKeys(ctx, query_before, rows_per_page) then close = true end

    DrawRowMenu(ctx, P)
    DrawTargetPopup(ctx, P)
    DrawTagPopups(ctx, P)
    DrawSettingsPopup(ctx, P)

    -- 사이드 패널 펼침 상태가 바뀌었으면 저장
    local tree_now = SerializeTree()
    if tree_now ~= saved_tree then
        saved_tree = tree_now
        Store.Set("tree_open", tree_now)
    end

    return close
end

return UI
end

return M
