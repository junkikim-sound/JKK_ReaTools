--========================================================
-- @title JKK_Theme
-- @author Junki Kim
-- @version 2.5.0 (Expanded Dark Presets & Tall Combo Lists)
--========================================================

local RPR = reaper
local EXT_SECTION = "JKK_Theme_v2"
local PRESET_SECTION = "JKK_Theme_Presets_v2"

----------------------------------------------------------
-- 100% Native Color Helpers (Strict Alpha Enforced)
----------------------------------------------------------
local function RGBA(r, g, b, a)
    if RPR.ImGui_ColorConvertDouble4ToU32 then
        return RPR.ImGui_ColorConvertDouble4ToU32(r / 255.0, g / 255.0, b / 255.0, (a or 255) / 255.0)
    else
        return ((r & 0xFF) << 24) | ((g & 0xFF) << 16) | ((b & 0xFF) << 8) | ((a or 255) & 0xFF)
    end
end

local function ShiftBrightness(col, delta_255, alpha_override_255)
    if not RPR.ImGui_ColorConvertU32ToDouble4 then return col end
    local r, g, b, a = RPR.ImGui_ColorConvertU32ToDouble4(col)
    local delta = delta_255 / 255.0
    local out_a = alpha_override_255 and (alpha_override_255 / 255.0) or a
    return RPR.ImGui_ColorConvertDouble4ToU32(
        math.max(0, math.min(1, r + delta)),
        math.max(0, math.min(1, g + delta)),
        math.max(0, math.min(1, b + delta)),
        math.max(0, math.min(1, out_a))
    )
end

local function BlendRGBA(col1, col2, t, alpha_override_255)
    if not RPR.ImGui_ColorConvertU32ToDouble4 then return col1 end
    local r1, g1, b1, a1 = RPR.ImGui_ColorConvertU32ToDouble4(col1)
    local r2, g2, b2, a2 = RPR.ImGui_ColorConvertU32ToDouble4(col2)
    local out_a = alpha_override_255 and (alpha_override_255 / 255.0) or (a1 + (a2 - a1) * t)
    return RPR.ImGui_ColorConvertDouble4ToU32(
        r1 + (r2 - r1) * t,
        g1 + (g2 - g1) * t,
        b1 + (b2 - b1) * t,
        math.max(0, math.min(1, out_a))
    )
end

----------------------------------------------------------
-- Default Configuration
----------------------------------------------------------
local DEFAULTS = {
    font_base_family   = "Arial", font_base_size   = 13,
    font_topbar_family = "Arial", font_topbar_size = 13,
    font_heading_family= "Arial", font_heading_size= 15,

    base_bg           = RGBA(37, 37, 37, 255),
    control_bg        = RGBA(53, 53, 53, 255),
    text_main         = RGBA(237, 237, 237, 255),
    accent_main       = RGBA(6, 143, 195, 255),

    btn_primary       = RGBA(35, 60, 79, 255),
    btn_primary_txt   = RGBA(237, 237, 237, 255),
    btn_confirm       = RGBA(36, 134, 111, 255),
    btn_highlight     = RGBA(255, 234, 112, 255),
    btn_highlight_txt = RGBA(5, 51, 89, 255),
    text_accent       = RGBA(227, 219, 142, 255),
}

local BUILTIN_PRESETS = {
    ["Default Dark"] = {
        font_base_family = "Arial", font_base_size = 13, font_topbar_family = "Arial", font_topbar_size = 13, font_heading_family = "Arial", font_heading_size = 15,
        base_bg = RGBA(37, 37, 37), control_bg = RGBA(53, 53, 53), text_main = RGBA(237, 237, 237), accent_main = RGBA(6, 143, 195),
        btn_primary = RGBA(35, 60, 79), btn_confirm = RGBA(36, 134, 111), btn_highlight = RGBA(255, 234, 112), btn_highlight_txt = RGBA(5, 51, 89), text_accent = RGBA(227, 219, 142),
    },
    ["Midnight Blue"] = {
        font_base_family = "Arial", font_base_size = 13, font_topbar_family = "Arial", font_topbar_size = 13, font_heading_family = "Arial", font_heading_size = 15,
        base_bg = RGBA(27, 32, 40), control_bg = RGBA(40, 49, 62), text_main = RGBA(232, 238, 245), accent_main = RGBA(56, 163, 232),
        btn_primary = RGBA(43, 76, 126), btn_confirm = RGBA(31, 138, 112), btn_highlight = RGBA(255, 209, 102), btn_highlight_txt = RGBA(20, 33, 61), text_accent = RGBA(244, 211, 94),
    },
    ["Warm Charcoal"] = {
        font_base_family = "Arial", font_base_size = 13, font_topbar_family = "Arial", font_topbar_size = 13, font_heading_family = "Arial", font_heading_size = 15,
        base_bg = RGBA(38, 35, 34), control_bg = RGBA(56, 51, 49), text_main = RGBA(240, 234, 230), accent_main = RGBA(217, 119, 66),
        btn_primary = RGBA(74, 59, 50), btn_confirm = RGBA(46, 125, 107), btn_highlight = RGBA(242, 193, 78), btn_highlight_txt = RGBA(43, 33, 24), text_accent = RGBA(232, 192, 125),
    },
    ["High Contrast"] = {
        font_base_family = "Arial", font_base_size = 13, font_topbar_family = "Arial", font_topbar_size = 13, font_heading_family = "Arial", font_heading_size = 15,
        base_bg = RGBA(22, 22, 22), control_bg = RGBA(42, 42, 42), text_main = RGBA(255, 255, 255), accent_main = RGBA(0, 180, 216),
        btn_primary = RGBA(29, 78, 137), btn_confirm = RGBA(27, 127, 92), btn_highlight = RGBA(255, 230, 0), btn_highlight_txt = RGBA(0, 0, 0), text_accent = RGBA(255, 230, 109),
    },
    ["Obsidian Teal"] = {
        font_base_family = "Arial", font_base_size = 13, font_topbar_family = "Arial", font_topbar_size = 13, font_heading_family = "Arial", font_heading_size = 15,
        base_bg = RGBA(27, 34, 37), control_bg = RGBA(43, 55, 59), text_main = RGBA(225, 235, 235), accent_main = RGBA(61, 170, 164),
        btn_primary = RGBA(41, 75, 80), btn_confirm = RGBA(48, 126, 104), btn_highlight = RGBA(224, 190, 95), btn_highlight_txt = RGBA(42, 43, 35), text_accent = RGBA(124, 194, 180),
    },
    ["Deep Forest"] = {
        font_base_family = "Arial", font_base_size = 13, font_topbar_family = "Arial", font_topbar_size = 13, font_heading_family = "Arial", font_heading_size = 15,
        base_bg = RGBA(29, 38, 33), control_bg = RGBA(46, 58, 50), text_main = RGBA(231, 237, 228), accent_main = RGBA(125, 170, 119),
        btn_primary = RGBA(49, 78, 62), btn_confirm = RGBA(72, 133, 94), btn_highlight = RGBA(222, 190, 102), btn_highlight_txt = RGBA(35, 43, 31), text_accent = RGBA(177, 198, 135),
    },
    ["Plum Dusk"] = {
        font_base_family = "Arial", font_base_size = 13, font_topbar_family = "Arial", font_topbar_size = 13, font_heading_family = "Arial", font_heading_size = 15,
        base_bg = RGBA(38, 31, 43), control_bg = RGBA(55, 45, 62), text_main = RGBA(238, 231, 242), accent_main = RGBA(168, 126, 190),
        btn_primary = RGBA(76, 55, 91), btn_confirm = RGBA(71, 125, 106), btn_highlight = RGBA(227, 190, 119), btn_highlight_txt = RGBA(46, 35, 43), text_accent = RGBA(194, 157, 204),
    },
    ["Ember Night"] = {
        font_base_family = "Arial", font_base_size = 13, font_topbar_family = "Arial", font_topbar_size = 13, font_heading_family = "Arial", font_heading_size = 15,
        base_bg = RGBA(42, 33, 30), control_bg = RGBA(61, 47, 42), text_main = RGBA(242, 231, 222), accent_main = RGBA(216, 126, 81),
        btn_primary = RGBA(83, 53, 42), btn_confirm = RGBA(67, 125, 93), btn_highlight = RGBA(245, 184, 89), btn_highlight_txt = RGBA(54, 36, 26), text_accent = RGBA(230, 160, 115),
    },
    ["Soft Linen"] = {
        base_bg = RGBA(246, 242, 233), control_bg = RGBA(229, 222, 209), text_main = RGBA(65, 58, 48), accent_main = RGBA(177, 128, 77),
        btn_primary = RGBA(218, 202, 175), btn_confirm = RGBA(139, 174, 139), btn_highlight = RGBA(247, 213, 133), btn_highlight_txt = RGBA(69, 52, 32), text_accent = RGBA(157, 111, 65),
    },
    ["Mint Garden"] = {
        base_bg = RGBA(237, 245, 239), control_bg = RGBA(218, 232, 222), text_main = RGBA(48, 65, 56), accent_main = RGBA(76, 145, 112),
        btn_primary = RGBA(190, 216, 199), btn_confirm = RGBA(125, 174, 142), btn_highlight = RGBA(247, 222, 145), btn_highlight_txt = RGBA(60, 57, 40), text_accent = RGBA(82, 132, 101),
    },
    ["Lavender Bloom"] = {
        base_bg = RGBA(243, 240, 249), control_bg = RGBA(226, 221, 239), text_main = RGBA(59, 53, 73), accent_main = RGBA(136, 113, 181),
        btn_primary = RGBA(207, 199, 229), btn_confirm = RGBA(157, 184, 166), btn_highlight = RGBA(248, 220, 158), btn_highlight_txt = RGBA(67, 55, 43), text_accent = RGBA(126, 104, 169),
    },
    ["Peach Sorbet"] = {
        base_bg = RGBA(250, 241, 234), control_bg = RGBA(237, 222, 211), text_main = RGBA(73, 55, 46), accent_main = RGBA(205, 125, 92),
        btn_primary = RGBA(231, 201, 183), btn_confirm = RGBA(155, 183, 148), btn_highlight = RGBA(250, 213, 134), btn_highlight_txt = RGBA(72, 51, 35), text_accent = RGBA(185, 109, 80),
    },
    ["Clear Sky"] = {
        base_bg = RGBA(238, 246, 251), control_bg = RGBA(219, 232, 241), text_main = RGBA(47, 62, 76), accent_main = RGBA(71, 143, 190),
        btn_primary = RGBA(192, 217, 234), btn_confirm = RGBA(151, 192, 173), btn_highlight = RGBA(249, 220, 139), btn_highlight_txt = RGBA(53, 57, 49), text_accent = RGBA(82, 132, 168),
    },
    ["Rosewater"] = {
        base_bg = RGBA(249, 241, 245), control_bg = RGBA(235, 222, 231), text_main = RGBA(68, 53, 64), accent_main = RGBA(183, 112, 151),
        btn_primary = RGBA(225, 197, 215), btn_confirm = RGBA(157, 185, 160), btn_highlight = RGBA(249, 219, 147), btn_highlight_txt = RGBA(70, 51, 55), text_accent = RGBA(164, 97, 136),
    },
}

local cfg = {}
for k, v in pairs(DEFAULTS) do cfg[k] = v end
local last_loaded_revision = -1

local function GetRevision() return tonumber(RPR.GetExtState(EXT_SECTION, "revision")) or 0 end

local function LoadConfig(force)
    local rev = GetRevision()
    if not force and rev == last_loaded_revision and last_loaded_revision ~= -1 then return false end
    last_loaded_revision = rev

    for k, default_val in pairs(DEFAULTS) do
        local saved = RPR.GetExtState(EXT_SECTION, k)
        if saved == "" then
            cfg[k] = default_val
        elseif type(default_val) == "number" then
            if k:find("_size") then
                cfg[k] = tonumber(saved) or default_val
            else
                cfg[k] = tonumber(saved, 16) or tonumber(saved) or default_val
            end
        else
            cfg[k] = saved
        end
    end
    return true
end

local function SaveConfig()
    for k, val in pairs(cfg) do
        if type(val) == "number" then
            if k:find("_size") then RPR.SetExtState(EXT_SECTION, k, tostring(val), true)
            else RPR.SetExtState(EXT_SECTION, k, string.format("%08X", val), true) end
        else
            RPR.SetExtState(EXT_SECTION, k, tostring(val), true)
        end
    end
    local next_rev = GetRevision() + 1
    RPR.SetExtState(EXT_SECTION, "revision", tostring(next_rev), true)
    last_loaded_revision = next_rev
end

local function ResetToDefaults()
    for k, v in pairs(DEFAULTS) do cfg[k] = v end
    SaveConfig()
end

LoadConfig(true)

----------------------------------------------------------
-- Smart Font Manager
----------------------------------------------------------
local ctx_font_cache = setmetatable({}, { __mode = "k" })

local function EnsureContextFonts(ctx)
    if not ctx then return nil end
    local entry = ctx_font_cache[ctx]
    if not entry then entry = {}; ctx_font_cache[ctx] = entry end

    local function setup_font(role_key)
        local family = cfg["font_"..role_key.."_family"] or "Arial"
        if entry[role_key.."_family"] ~= family or not entry[role_key.."_font"] then
            if entry[role_key.."_font"] and RPR.ImGui_Detach then pcall(RPR.ImGui_Detach, ctx, entry[role_key.."_font"]) end
            entry[role_key.."_font"] = RPR.ImGui_CreateFont(family, 32)
            RPR.ImGui_Attach(ctx, entry[role_key.."_font"])
            entry[role_key.."_family"] = family
        end
    end

    setup_font("base")
    setup_font("topbar")
    setup_font("heading")

    return entry
end

local function PushFont(ctx, scale, role)
    local entry = EnsureContextFonts(ctx)
    if not entry then return end
    
    local font_obj, base_size
    if role == "heading" then 
        font_obj = entry.heading_font; base_size = cfg.font_heading_size
    elseif role == "topbar" or role == "input" then 
        font_obj = entry.topbar_font; base_size = cfg.font_topbar_size
    else 
        font_obj = entry.base_font; base_size = cfg.font_base_size 
    end
    
    local final_size = math.max(6, base_size * (scale or 1.0))
    RPR.ImGui_PushFont(ctx, font_obj, final_size)
end
local function PopFont(ctx) RPR.ImGui_PopFont(ctx) end

----------------------------------------------------------
-- Semantic Style Helpers
----------------------------------------------------------
local function GetButtonPalette(kind)
    if kind == "confirm" then
        local base = cfg.btn_confirm
        return base, ShiftBrightness(base, 18), ShiftBrightness(base, -15), nil
    elseif kind == "highlight" then
        local base = cfg.btn_highlight
        return base, ShiftBrightness(base, -16), ShiftBrightness(base, -36), cfg.btn_highlight_txt
    else
        local base = cfg.btn_primary
        return base, ShiftBrightness(base, 28), ShiftBrightness(base, -25), cfg.btn_primary_txt
    end
end

local pushed_button_text_stack = {}
local function PushButton(ctx, kind)
    local base, hov, act, txt = GetButtonPalette(kind)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Button(), base)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonHovered(), hov)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonActive(), act)
    if txt then
        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), txt)
        pushed_button_text_stack[#pushed_button_text_stack + 1] = true
    else
        pushed_button_text_stack[#pushed_button_text_stack + 1] = false
    end
end
local function PopButton(ctx)
    local had_text = table.remove(pushed_button_text_stack)
    RPR.ImGui_PopStyleColor(ctx, had_text and 4 or 3)
end

local function GetColor(role)
    if role == "accent" or role == "text_accent" then return cfg.text_accent
    elseif role == "status" then return BlendRGBA(cfg.text_main, cfg.base_bg, 0.22, 255)
    elseif role == "slider" then return cfg.accent_main end
    return cfg[role] or cfg.text_main
end
local function PushText(ctx, role) RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), GetColor(role)) end
local function PopText(ctx) RPR.ImGui_PopStyleColor(ctx, 1) end

local function GetSplitterColor(active, hovered)
    if active then return cfg.accent_main
    elseif hovered then return ShiftBrightness(cfg.control_bg, 52)
    else return ShiftBrightness(cfg.control_bg, 7) end
end

----------------------------------------------------------
-- Main Theme Application
----------------------------------------------------------
local function ApplyTheme(ctx, scale)
    LoadConfig(false)
    EnsureContextFonts(ctx)

    local s = scale or 1
    local base_bg, ctrl_bg, text_main, accent = cfg.base_bg, cfg.control_bg, cfg.text_main, cfg.accent_main

    local child_bg      = ShiftBrightness(base_bg, -5)
    local title_active  = ShiftBrightness(base_bg, -12)
    local popup_bg      = ShiftBrightness(base_bg, -17, 240)
    local ctrl_hover    = ShiftBrightness(ctrl_bg, 16)
    local ctrl_active   = ShiftBrightness(ctrl_bg, 32)
    local border_col    = ShiftBrightness(ctrl_bg, 27)
    local separator_col = ShiftBrightness(ctrl_bg, -3)
    local text_disabled = BlendRGBA(text_main, base_bg, 0.55, 255)
    local accent_bright = ShiftBrightness(accent, 45)
    local accent_dark   = ShiftBrightness(accent, -65)

    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_Alpha(),                       1)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_DisabledAlpha(),               0.6)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_WindowPadding(),               8 * s, 8 * s)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_WindowRounding(),              8 * s)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_WindowBorderSize(),            1)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_WindowMinSize(),               32, 32)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_WindowTitleAlign(),            0, 0.5)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ChildRounding(),               12 * s)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ChildBorderSize(),             1)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_PopupRounding(),               8 * s)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_PopupBorderSize(),             1)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_FramePadding(),                4 * s, 3 * s)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_FrameRounding(),               12 * s)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_FrameBorderSize(),             0)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ItemSpacing(),                 8 * s, 4 * s)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ItemInnerSpacing(),            4 * s, 4 * s)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_IndentSpacing(),               22 * s)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_CellPadding(),                 0, 2 * s)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ScrollbarSize(),               14 * s)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ScrollbarRounding(),           12 * s)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_GrabMinSize(),                 15 * s)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_GrabRounding(),                12 * s)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ImageBorderSize(),             0)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_TabRounding(),                 6 * s)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_TabBorderSize(),               0)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_TabBarBorderSize(),            1)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_TabBarOverlineSize(),          1)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_TableAngledHeadersAngle(),     0.610865)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_TableAngledHeadersTextAlign(), 0.5, 0)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_TreeLinesSize(),               1)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_TreeLinesRounding(),           12)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ButtonTextAlign(),             0.5, 0.5)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_SelectableTextAlign(),         0, 0)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_SeparatorTextBorderSize(),     2)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_SeparatorTextAlign(),          0, 0.5)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_SeparatorTextPadding(),        20 * s, 3 * s)

    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(),                      text_main)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TextDisabled(),              text_disabled)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_WindowBg(),                  base_bg)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ChildBg(),                   child_bg)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_PopupBg(),                   popup_bg)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Border(),                    border_col)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_BorderShadow(),              RGBA(128, 128, 128, 255))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_FrameBg(),                   ctrl_bg)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_FrameBgHovered(),            ctrl_hover)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_FrameBgActive(),             ctrl_active)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TitleBg(),                   base_bg)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TitleBgActive(),             title_active)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TitleBgCollapsed(),          RGBA(0, 0, 0, 130))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_MenuBarBg(),                 ctrl_bg)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ScrollbarBg(),               RGBA(0, 0, 0, 0))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ScrollbarGrab(),             accent)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ScrollbarGrabHovered(),      accent_bright)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ScrollbarGrabActive(),       accent_dark)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_CheckMark(),                 accent)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_SliderGrab(),                accent)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_SliderGrabActive(),          accent_bright)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Button(),                    ctrl_bg)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonHovered(),             ctrl_hover)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonActive(),              ctrl_active)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Header(),                    base_bg)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_HeaderHovered(),             ctrl_hover)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_HeaderActive(),              ctrl_active)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Separator(),                 separator_col)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_SeparatorHovered(),          separator_col)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_SeparatorActive(),           separator_col)
    
    local resize_grip_col = accent
    if RPR.ImGui_ColorConvertU32ToDouble4 then
        local rA, gA, bA, _ = RPR.ImGui_ColorConvertU32ToDouble4(accent)
        resize_grip_col = RPR.ImGui_ColorConvertDouble4ToU32(rA, gA, bA, 0.94)
    end
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ResizeGrip(),                resize_grip_col)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ResizeGripHovered(),         accent_bright)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ResizeGripActive(),          accent_bright)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_InputTextCursor(),           text_main)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TabHovered(),                ctrl_active)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Tab(),                       ctrl_bg)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TabSelected(),               accent)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TabSelectedOverline(),       ctrl_active)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TabDimmed(),                 ShiftBrightness(base_bg, -14, 248))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TabDimmedSelected(),         BlendRGBA(base_bg, accent, 0.35, 255))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TabDimmedSelectedOverline(), RGBA(128, 128, 128, 0))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_DockingPreview(),            RGBA(23, 156, 128, 179))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_DockingEmptyBg(),            ShiftBrightness(base_bg, 14))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_PlotLines(),                 RGBA(156, 156, 156, 255))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_PlotLinesHovered(),          RGBA(176, 108, 88, 255))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_PlotHistogram(),             RGBA(178, 152, 89, 255))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_PlotHistogramHovered(),      RGBA(90, 151, 82, 255))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TableHeaderBg(),             base_bg)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TableBorderStrong(),         border_col)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TableBorderLight(),          RGBA(65, 65, 65, 0))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TableRowBg(),                RGBA(0, 0, 0, 0))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TableRowBgAlt(),             RGBA(255, 255, 255, 15))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TextLink(),                  RGBA(160, 160, 230, 255))
    
    local text_sel_col = accent
    if RPR.ImGui_ColorConvertU32ToDouble4 then
        local rA, gA, bA, _ = RPR.ImGui_ColorConvertU32ToDouble4(accent)
        text_sel_col = RPR.ImGui_ColorConvertDouble4ToU32(rA, gA, bA, 0.35)
    end
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TextSelectedBg(),            text_sel_col)
    
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TreeLines(),                 RGBA(110, 110, 128, 128))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_DragDropTarget(),            cfg.text_accent)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_NavCursor(),                 RGBA(23, 156, 128, 255))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_NavWindowingHighlight(),     RGBA(255, 255, 255, 179))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_NavWindowingDimBg(),         RGBA(204, 204, 204, 51))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ModalWindowDimBg(),          RGBA(204, 204, 204, 89))

    return 36, 60
end

----------------------------------------------------------
-- Preset Storage Helpers
----------------------------------------------------------
local function GetCustomPresetNames()
    local raw = RPR.GetExtState(PRESET_SECTION, "_names")
    local list = {}
    for name in raw:gmatch("([^\31]+)") do
        if name ~= "" then list[#list + 1] = name end
    end
    return list
end

local function SaveCustomPresetNames(list)
    RPR.SetExtState(PRESET_SECTION, "_names", table.concat(list, "\31"), true)
end

local function SerializeCurrentConfig()
    local parts = {}
    for k, val in pairs(cfg) do
        if type(val) == "number" then
            if k:find("_size") then parts[#parts + 1] = string.format("%s=%s", k, val)
            else parts[#parts + 1] = string.format("%s=%08X", k, val) end
        else
            parts[#parts + 1] = string.format("%s=%s", k, tostring(val))
        end
    end
    return table.concat(parts, ";")
end

local function SavePreset(name)
    if not name or name == "" or BUILTIN_PRESETS[name] then return false end
    local names = GetCustomPresetNames()
    local exists = false
    for _, n in ipairs(names) do if n == name then exists = true break end end
    if not exists then names[#names + 1] = name; SaveCustomPresetNames(names) end
    RPR.SetExtState(PRESET_SECTION, "data_" .. name, SerializeCurrentConfig(), true)
    RPR.SetExtState(EXT_SECTION, "selected_preset", name, true)
    return true
end

local function LoadPreset(name)
    if BUILTIN_PRESETS[name] then
        for k, v in pairs(DEFAULTS) do cfg[k] = BUILTIN_PRESETS[name][k] or v end
        if not BUILTIN_PRESETS[name].btn_primary_txt then
            cfg.btn_primary_txt = cfg.text_main
        end
        RPR.SetExtState(EXT_SECTION, "selected_preset", name, true)
        SaveConfig()
        return true
    end
    local raw = RPR.GetExtState(PRESET_SECTION, "data_" .. name)
    if raw == "" then return false end
    for k, v in pairs(DEFAULTS) do cfg[k] = v end
    for pair in raw:gmatch("([^;]+)") do
        local k, v = pair:match("^([^=]+)=(.*)$")
        if k and DEFAULTS[k] ~= nil then
            if type(DEFAULTS[k]) == "number" then
                if k:find("_size") then cfg[k] = tonumber(v) or DEFAULTS[k]
                else cfg[k] = tonumber(v, 16) or tonumber(v) or DEFAULTS[k] end
            else cfg[k] = v end
        end
    end
    RPR.SetExtState(EXT_SECTION, "selected_preset", name, true)
    SaveConfig()
    return true
end

local function DeletePreset(name)
    if not name or BUILTIN_PRESETS[name] then return end
    local names = GetCustomPresetNames()
    local filtered = {}
    for _, n in ipairs(names) do if n ~= name then filtered[#filtered + 1] = n end end
    SaveCustomPresetNames(filtered)
    RPR.DeleteExtState(PRESET_SECTION, "data_" .. name, true)
end

----------------------------------------------------------
-- Fluid Editor Window
----------------------------------------------------------
local FONT_SUGGESTIONS = { 
    "Arial", "Segoe UI", "Malgun Gothic", "Pretendard", "Consolas", "Roboto", "Helvetica", 
    "Verdana", "Tahoma", "Trebuchet MS", "AppleGothic", "SF Pro", "Times New Roman", "Georgia", 
    "Courier New", "Comic Sans MS", "Impact", "Lucida Console", "Gothic A1", "NanumGothic"
}

local editor_ctx = nil
local editor_open = false
local saved_preset = RPR.GetExtState(EXT_SECTION, "selected_preset")
local selected_preset = (saved_preset ~= "") and saved_preset or "Default Dark"
local new_preset_name = ""

local function ColorPickerRow(ctx, label, key, tooltip)
    RPR.ImGui_AlignTextToFramePadding(ctx)
    RPR.ImGui_Text(ctx, label)
    if tooltip and RPR.ImGui_IsItemHovered(ctx) then RPR.ImGui_SetTooltip(ctx, tooltip) end

    local current_col = cfg[key] or RGBA(237, 237, 237, 255)
    
    local hex_str = "#FFFFFF"
    if RPR.ImGui_ColorConvertU32ToDouble4 then
        local r, g, b, _ = RPR.ImGui_ColorConvertU32ToDouble4(current_col)
        hex_str = string.format("#%02X%02X%02X", math.floor(r*255+0.5), math.floor(g*255+0.5), math.floor(b*255+0.5))
    end
    
    local text_w = select(1, RPR.ImGui_CalcTextSize(ctx, hex_str))
    local frame_h = RPR.ImGui_GetFrameHeight(ctx)
    local spacing = 8
    local controls_w = text_w + spacing + frame_h

    RPR.ImGui_SameLine(ctx, 0, 0)
    local win_w = RPR.ImGui_GetWindowWidth(ctx)
    local padding_x = select(1, RPR.ImGui_GetStyleVar(ctx, RPR.ImGui_StyleVar_WindowPadding()))
    local target_x = win_w - padding_x - controls_w
    RPR.ImGui_SetCursorPosX(ctx, math.max(RPR.ImGui_GetCursorPosX(ctx) + 10, target_x))

    RPR.ImGui_TextDisabled(ctx, hex_str)
    RPR.ImGui_SameLine(ctx, 0, spacing)

    -- ColorEdit3는 0xXXRRGGBB 형식(RGB 24-bit)을 사용한다.
    -- Theme 내부 색상은 0xRRGGBBAA 형식이므로 호출 전/후 변환해야 한다.
    local flags = RPR.ImGui_ColorEditFlags_NoInputs()
    local edit_rgb = (current_col >> 8) & 0x00FFFFFF
    local changed, new_rgb = RPR.ImGui_ColorEdit3(ctx, "##col_" .. key, edit_rgb, flags)
    if changed then
        -- RGB를 0xRRGGBBFF로 변환해 저장 (완전 불투명)
        cfg[key] = ((new_rgb & 0x00FFFFFF) << 8) | 0xFF
        SaveConfig()
    end
end

local function FontSelectorRow(ctx, label, role_key)
    local input_w = 110
    local combo_w = 24
    local size_w = 55
    local spacing = 8
    local controls_w = size_w + spacing + input_w + spacing + combo_w

    RPR.ImGui_AlignTextToFramePadding(ctx)
    RPR.ImGui_Text(ctx, label)
    
    RPR.ImGui_SameLine(ctx, 0, 0)
    local win_w = RPR.ImGui_GetWindowWidth(ctx)
    local padding_x = select(1, RPR.ImGui_GetStyleVar(ctx, RPR.ImGui_StyleVar_WindowPadding()))
    local target_x = win_w - padding_x - controls_w
    RPR.ImGui_SetCursorPosX(ctx, math.max(RPR.ImGui_GetCursorPosX(ctx) + 10, target_x))

    RPR.ImGui_SetNextItemWidth(ctx, size_w)
    local sz_changed, new_sz = RPR.ImGui_InputInt(ctx, "##sz_"..role_key, cfg["font_"..role_key.."_size"], 0, 0)
    if sz_changed then
        cfg["font_"..role_key.."_size"] = math.max(8, math.min(72, new_sz))
        SaveConfig()
    end

    RPR.ImGui_SameLine(ctx, 0, spacing)
    RPR.ImGui_SetNextItemWidth(ctx, input_w)
    local changed, new_val = RPR.ImGui_InputText(ctx, "##font_" .. role_key, cfg["font_"..role_key.."_family"])
    if changed then cfg["font_"..role_key.."_family"] = new_val end
    if RPR.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        if cfg["font_"..role_key.."_family"] == "" then cfg["font_"..role_key.."_family"] = DEFAULTS["font_"..role_key.."_family"] end
        SaveConfig()
    end

    RPR.ImGui_SameLine(ctx, 0, spacing)
    RPR.ImGui_SetNextItemWidth(ctx, combo_w)
    -- HeightLargest: 가능한 화면 높이를 활용해 폰트 목록을 스크롤 없이 표시한다.
    local font_combo_flags = RPR.ImGui_ComboFlags_HeightLargest()
        | RPR.ImGui_ComboFlags_NoPreview()
    if RPR.ImGui_BeginCombo(ctx, "##font_pick_" .. role_key, "", font_combo_flags) then
        for _, fname in ipairs(FONT_SUGGESTIONS) do
            if RPR.ImGui_Selectable(ctx, fname, cfg["font_"..role_key.."_family"] == fname) then
                cfg["font_"..role_key.."_family"] = fname
                SaveConfig()
            end
        end
        RPR.ImGui_EndCombo(ctx)
    end
end

local function EditorLoop()
    if not editor_open or not editor_ctx then
        if editor_ctx and RPR.ImGui_DestroyContext then RPR.ImGui_DestroyContext(editor_ctx) end
        editor_ctx = nil
        return
    end

    RPR.ImGui_SetNextWindowSizeConstraints(editor_ctx, 400, 590, 9999, 9999)
    RPR.ImGui_SetNextWindowSize(editor_ctx, 400, 590, RPR.ImGui_Cond_FirstUseEver())
    
    local sp, cp = ApplyTheme(editor_ctx, 1.0)
    local visible, open_flag = RPR.ImGui_Begin(editor_ctx, "JKK Theme Manager", editor_open, RPR.ImGui_WindowFlags_NoCollapse())

    if visible then
        PushFont(editor_ctx, 1.0, "base")
        local avail_w = RPR.ImGui_GetContentRegionAvail(editor_ctx)
        local spacing = 8
        local action_btn_w = 65
        local combined_save_w = action_btn_w * 2 + spacing
        local combo_w = math.max(10, avail_w - combined_save_w - spacing)

        -- 1. Presets Section
        PushText(editor_ctx, "accent")
        RPR.ImGui_Text(editor_ctx, "Presets")
        PopText(editor_ctx)

        RPR.ImGui_SetNextItemWidth(editor_ctx, combo_w)
        -- HeightLargest로 팝업을 화면에서 사용할 수 있는 최대 높이까지 확장한다.
        if RPR.ImGui_BeginCombo(
            editor_ctx, "##PresetCombo", selected_preset,
            RPR.ImGui_ComboFlags_HeightLargest()
        ) then
            RPR.ImGui_SeparatorText(editor_ctx, "DARK")
            for _, bname in ipairs({
                "Default Dark", "Midnight Blue", "Warm Charcoal", "High Contrast",
                "Obsidian Teal", "Deep Forest", "Plum Dusk", "Ember Night"
            }) do
                if RPR.ImGui_Selectable(editor_ctx, bname, selected_preset == bname) then
                    selected_preset = bname; LoadPreset(bname)
                end
            end

            RPR.ImGui_SeparatorText(editor_ctx, "LIGHT")
            for _, bname in ipairs({
                "Soft Linen", "Mint Garden", "Lavender Bloom", "Peach Sorbet", "Clear Sky", "Rosewater"
            }) do
                if RPR.ImGui_Selectable(editor_ctx, bname, selected_preset == bname) then
                    selected_preset = bname; LoadPreset(bname)
                end
            end

            local custom_presets = GetCustomPresetNames()
            if #custom_presets > 0 then
                RPR.ImGui_SeparatorText(editor_ctx, "CUSTOM")
                for _, cname in ipairs(custom_presets) do
                    if RPR.ImGui_Selectable(editor_ctx, cname, selected_preset == cname) then
                        selected_preset = cname; LoadPreset(cname)
                    end
                end
            end
            RPR.ImGui_EndCombo(editor_ctx)
        end
        RPR.ImGui_SameLine(editor_ctx, 0, spacing)
        PushButton(editor_ctx, "confirm")
        if RPR.ImGui_Button(editor_ctx, "Load", action_btn_w, 0) then LoadPreset(selected_preset) end
        PopButton(editor_ctx)
        RPR.ImGui_SameLine(editor_ctx, 0, spacing)
        if RPR.ImGui_Button(editor_ctx, "Delete", action_btn_w, 0) then
            DeletePreset(selected_preset)
            selected_preset = "Default Dark"
            RPR.SetExtState(EXT_SECTION, "selected_preset", "Default Dark", true)
        end

        RPR.ImGui_SetNextItemWidth(editor_ctx, combo_w)
        local _, buf = RPR.ImGui_InputTextWithHint(editor_ctx, "##NewPresetName", "New preset name...", new_preset_name)
        new_preset_name = buf
        RPR.ImGui_SameLine(editor_ctx, 0, spacing)
        PushButton(editor_ctx, "primary")
        if RPR.ImGui_Button(editor_ctx, "Save Preset", combined_save_w, 0) and new_preset_name ~= "" then
            if SavePreset(new_preset_name) then selected_preset = new_preset_name; new_preset_name = "" end
        end
        PopButton(editor_ctx)

        RPR.ImGui_Spacing(editor_ctx); RPR.ImGui_Separator(editor_ctx); RPR.ImGui_Spacing(editor_ctx)

        -- 2. Fonts Section
        PushText(editor_ctx, "accent")
        RPR.ImGui_Text(editor_ctx, "Fonts (Size & Family)")
        PopText(editor_ctx)

        FontSelectorRow(editor_ctx, "UI Main (Base) Font", "base")
        FontSelectorRow(editor_ctx, "Top Bar & Input Font", "topbar")
        FontSelectorRow(editor_ctx, "Highlight (Title) Font", "heading")

        RPR.ImGui_Spacing(editor_ctx); RPR.ImGui_Separator(editor_ctx); RPR.ImGui_Spacing(editor_ctx)

        -- 3. Smart Base Tones Section
        PushText(editor_ctx, "accent")
        RPR.ImGui_Text(editor_ctx, "Smart Base Tones (Auto-Grouped)")
        PopText(editor_ctx)

        ColorPickerRow(editor_ctx, "Window & Panel Base", "base_bg", "메인 창과 패널의 배경색")
        ColorPickerRow(editor_ctx, "Control & Input Tone", "control_bg", "버튼, 입력창, 슬라이더 트랙 등의 배경색")
        ColorPickerRow(editor_ctx, "Base Text Tone", "text_main", "일반 글씨색 (명도 조절로 비활성 텍스트도 자동 계산)")
        ColorPickerRow(editor_ctx, "Slider & Accent Handle", "accent_main", "슬라이더 핸들, 체크마크, 선택된 탭 등의 포인트 색")

        RPR.ImGui_Spacing(editor_ctx); RPR.ImGui_Separator(editor_ctx); RPR.ImGui_Spacing(editor_ctx)

        -- 4. Semantic Colors Section
        PushText(editor_ctx, "accent")
        RPR.ImGui_Text(editor_ctx, "Semantic Highlights")
        PopText(editor_ctx)

        ColorPickerRow(editor_ctx, "Important Button", "btn_primary", "Reverse, Render Take, Loopmaker, Renamer 등")
        ColorPickerRow(editor_ctx, "Important Button Text", "btn_primary_txt", "Important 버튼 내부의 글씨색")
        ColorPickerRow(editor_ctx, "Confirm Button", "btn_confirm", "Apply, Shuffle Order, Split 등 결정을 내리는 버튼")
        ColorPickerRow(editor_ctx, "Highlight Button", "btn_highlight", "Home 버튼 등 가장 눈에 띄어야 하는 버튼")
        ColorPickerRow(editor_ctx, "Important Text", "text_accent", "패널 헤더 타이틀, 활성 상태 표시 텍스트 등")
        
        RPR.ImGui_Spacing(editor_ctx); RPR.ImGui_Separator(editor_ctx); RPR.ImGui_Spacing(editor_ctx)

        -- 5. Fluid Bottom Buttons
        local bottom_btn_w = math.floor((avail_w - spacing * 2) / 3)

        PushButton(editor_ctx, "primary")
        RPR.ImGui_Button(editor_ctx, "Important", bottom_btn_w, 24)
        PopButton(editor_ctx)
        
        RPR.ImGui_SameLine(editor_ctx, 0, spacing)
        PushButton(editor_ctx, "confirm")
        RPR.ImGui_Button(editor_ctx, "Confirm", bottom_btn_w, 24)
        PopButton(editor_ctx)
        
        RPR.ImGui_SameLine(editor_ctx, 0, spacing)
        PushButton(editor_ctx, "highlight")
        RPR.ImGui_Button(editor_ctx, "Highlight", bottom_btn_w, 24)
        PopButton(editor_ctx)

        RPR.ImGui_Spacing(editor_ctx)
        if RPR.ImGui_Button(editor_ctx, "Reset All to Default", -1, 26) then
            ResetToDefaults()
            selected_preset = "Default Dark"
            RPR.SetExtState(EXT_SECTION, "selected_preset", "Default Dark", true)
        end

        PopFont(editor_ctx)
    end

    RPR.ImGui_End(editor_ctx)
    RPR.ImGui_PopStyleVar(editor_ctx, sp)
    RPR.ImGui_PopStyleColor(editor_ctx, cp)

    editor_open = open_flag
    if editor_open then RPR.defer(EditorLoop)
    else if editor_ctx and RPR.ImGui_DestroyContext then RPR.ImGui_DestroyContext(editor_ctx) end; editor_ctx = nil end
end

local function OpenEditor()
    if editor_open and editor_ctx then return end
    editor_ctx = RPR.ImGui_CreateContext("JKK_Theme_Manager")
    editor_open = true
    RPR.defer(EditorLoop)
end

local Theme = {
    ApplyTheme = ApplyTheme, PushButton = PushButton, PopButton = PopButton,
    PushText = PushText, PopText = PopText, PushFont = PushFont, PopFont = PopFont,
    GetColor = GetColor, GetSplitterColor = GetSplitterColor,
    OpenEditor = OpenEditor, ResetToDefaults = ResetToDefaults,
}
_G.JKK_Theme = Theme
if debug.getinfo(2, "S") == nil then OpenEditor() end

return Theme