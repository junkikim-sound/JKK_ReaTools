--========================================================
-- @title JKK_Theme_Core
-- @author Junki Kim
-- @noindex
--========================================================

local RPR = reaper
local core_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local WindowChrome = dofile(core_dir .. "JKK_WindowChrome.lua")
local EXT_SECTION = "JKK_Theme"
local PRESET_SECTION = "JKK_Theme_Presets"

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
-- Default Configuration & Built-in Presets
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

local DARK_PRESET_ORDER = {
    "Default Dark", "Midnight Blue", "Warm Charcoal", "High Contrast",
    "Obsidian Teal", "Deep Forest", "Plum Dusk"
}

local LIGHT_PRESET_ORDER = {
    "Soft Linen", "Mint Garden", "Lavender Bloom", "Peach Sorbet", "Clear Sky",
    "Olive Parchment", "Blue Porcelain"
}

-- Bold high-chroma palettes: three dark vivid themes first, followed by four light vivid themes.
-- Keep these in a single VIVID group in the manager and the prev/next cycle.
local VIVID_PRESET_ORDER = {
    "Ultraviolet Club", "Afterglow Circuit", "Neon Lagoon",
    "Acid Gallery", "Bubblegum Terminal", "Cobalt Fiesta", "Tropic Pulse"
}

-- Vivid-specific selected-tab treatment: bright slider handles should never
-- become same-color tab backgrounds with unreadable text.
local VIVID_PRESET_MODE = {
    ["Ultraviolet Club"] = "dark", ["Afterglow Circuit"] = "dark", ["Neon Lagoon"] = "dark",
    ["Acid Gallery"] = "light", ["Bubblegum Terminal"] = "light",
    ["Cobalt Fiesta"] = "light", ["Tropic Pulse"] = "light",
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
    -- LIGHT: deeper, desaturated palettes comparable in density to Peach Sorbet.
    ["Olive Parchment"] = {
        base_bg = RGBA(226, 223, 199), control_bg = RGBA(202, 200, 173), text_main = RGBA(52, 58, 42), accent_main = RGBA(112, 126, 65),
        btn_primary = RGBA(161, 170, 123), btn_primary_txt = RGBA(46, 55, 38), btn_confirm = RGBA(135, 169, 126), btn_highlight = RGBA(234, 196, 113), btn_highlight_txt = RGBA(65, 51, 29), text_accent = RGBA(90, 109, 53),
    },
    ["Blue Porcelain"] = {
        base_bg = RGBA(216, 228, 231), control_bg = RGBA(187, 207, 216), text_main = RGBA(43, 61, 73), accent_main = RGBA(53, 119, 153),
        btn_primary = RGBA(150, 180, 199), btn_primary_txt = RGBA(39, 62, 80), btn_confirm = RGBA(133, 177, 167), btn_highlight = RGBA(239, 195, 125), btn_highlight_txt = RGBA(55, 48, 39), text_accent = RGBA(54, 109, 140),
    },
    -- VIVID / 2026 contrast rework:
    -- base_bg: window canvas; control_bg: slider track, combo/input frame and normal buttons.
    -- The slider track is intentionally a different hue AND visibly different value
    -- from the window surface, while every surface keeps readable base text.
    -- accent_main: slider handle/checkmark (distinct from control_bg).
    -- TabSelected is mapped separately in ApplyTheme so vivid handles do not
    -- become unreadable tab backgrounds. Keep theme names/order unchanged.
    -- 1) Ultraviolet: midnight aubergine / orchid-plum rails / fluorescent citron.
    ["Ultraviolet Club"] = {
        base_bg = RGBA(28, 14, 50), control_bg = RGBA(99, 50, 102), text_main = RGBA(255, 242, 249), accent_main = RGBA(218, 255, 93),
        btn_primary = RGBA(79, 50, 127), btn_primary_txt = RGBA(255, 255, 255), btn_confirm = RGBA(11, 96, 118),
        btn_highlight = RGBA(255, 105, 204), btn_highlight_txt = RGBA(37, 12, 51), text_accent = RGBA(230, 255, 138),
    },
    -- 2) Afterglow: noir-cherry / toasted copper rails / ice-blue electricity.
    ["Afterglow Circuit"] = {
        base_bg = RGBA(37, 13, 22), control_bg = RGBA(117, 64, 45), text_main = RGBA(255, 242, 232), accent_main = RGBA(75, 236, 255),
        btn_primary = RGBA(34, 78, 123), btn_primary_txt = RGBA(255, 255, 255), btn_confirm = RGBA(17, 101, 90),
        btn_highlight = RGBA(255, 185, 102), btn_highlight_txt = RGBA(48, 22, 32), text_accent = RGBA(255, 208, 152),
    },
    -- 3) Neon Lagoon: deep navy / petrol-teal rails / luminous pastel-coral handles.
    ["Neon Lagoon"] = {
        base_bg = RGBA(7, 31, 51), control_bg = RGBA(35, 89, 106), text_main = RGBA(234, 255, 255), accent_main = RGBA(255, 186, 208),
        btn_primary = RGBA(104, 49, 124), btn_primary_txt = RGBA(255, 255, 255), btn_confirm = RGBA(109, 53, 106),
        btn_highlight = RGBA(131, 255, 227), btn_highlight_txt = RGBA(18, 47, 57), text_accent = RGBA(142, 255, 232),
    },
    -- 4) Acid: citron window / lavender slider rails / deep purple grab.
    ["Acid Gallery"] = {
        base_bg = RGBA(217, 243, 92), control_bg = RGBA(183, 155, 220), text_main = RGBA(38, 19, 61), accent_main = RGBA(74, 35, 123),
        btn_primary = RGBA(77, 26, 114), btn_primary_txt = RGBA(255, 255, 255), btn_confirm = RGBA(255, 155, 109),
        btn_highlight = RGBA(255, 232, 128), btn_highlight_txt = RGBA(38, 19, 61), text_accent = RGBA(77, 26, 114),
    },
    -- 5) Bubblegum: bubblegum pink / saturated cerulean rails / indigo grab.
    ["Bubblegum Terminal"] = {
        base_bg = RGBA(255, 173, 204), control_bg = RGBA(88, 180, 223), text_main = RGBA(36, 20, 54), accent_main = RGBA(53, 31, 152),
        btn_primary = RGBA(40, 63, 154), btn_primary_txt = RGBA(255, 255, 255), btn_confirm = RGBA(255, 221, 88),
        btn_highlight = RGBA(214, 255, 107), btn_highlight_txt = RGBA(50, 27, 83), text_accent = RGBA(69, 34, 122),
    },
    -- 6) Cobalt: saturated sky-blue / mango-gold rails / ink-blue grab.
    ["Cobalt Fiesta"] = {
        base_bg = RGBA(105, 169, 250), control_bg = RGBA(255, 219, 121), text_main = RGBA(19, 40, 71), accent_main = RGBA(42, 50, 138),
        btn_primary = RGBA(38, 62, 154), btn_primary_txt = RGBA(255, 255, 255), btn_confirm = RGBA(157, 255, 173),
        btn_highlight = RGBA(255, 129, 109), btn_highlight_txt = RGBA(19, 40, 71), text_accent = RGBA(27, 44, 119),
    },
    -- 7) Tropic: aqua-jade window / orchid-rose rails / midnight-violet grab.
    ["Tropic Pulse"] = {
        base_bg = RGBA(67, 224, 190), control_bg = RGBA(194, 112, 168), text_main = RGBA(12, 34, 45), accent_main = RGBA(39, 19, 124),
        btn_primary = RGBA(75, 32, 107), btn_primary_txt = RGBA(255, 255, 255), btn_confirm = RGBA(255, 214, 108),
        btn_highlight = RGBA(255, 143, 93), btn_highlight_txt = RGBA(12, 34, 45), text_accent = RGBA(48, 16, 80),
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

    -- Preserve the original TabSelected behavior for all non-Vivid presets.
    -- For Vivid, choose a saturated tab color with legible text_main:
    -- dark Vivid uses the deep Important tone, light Vivid uses Confirm.
    local vivid_mode = VIVID_PRESET_MODE[RPR.GetExtState(EXT_SECTION, "selected_preset")]
    local selected_tab_bg = vivid_mode and (vivid_mode == "dark" and cfg.btn_primary or cfg.btn_confirm) or accent

    local child_bg      = ShiftBrightness(base_bg, -5)
    local title_active  = ShiftBrightness(base_bg, -12)
    local popup_bg      = ShiftBrightness(child_bg, -8, 255)
    if (popup_bg & 0xFFFFFF00) == 0 then popup_bg = RGBA(3, 3, 3, 255) end
    local ctrl_hover    = ShiftBrightness(ctrl_bg, 16)
    local ctrl_active   = ShiftBrightness(ctrl_bg, 32)
    local border_col    = ShiftBrightness(ctrl_bg, 27)
    local separator_col = ShiftBrightness(ctrl_bg, -3)
    local text_disabled = BlendRGBA(text_main, base_bg, 0.55, 255)
    -- Light Vivid has a dark grab on a colored, lighter slider rail.
    -- +45 would wash out the active grab and reduce its contrast.
    local accent_bright = ShiftBrightness(accent, vivid_mode == "light" and 12 or 45)
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
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TabSelected(),               selected_tab_bg)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TabSelectedOverline(),       vivid_mode and accent or ctrl_active)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TabDimmed(),                 ShiftBrightness(base_bg, -14, 248))
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_TabDimmedSelected(),         BlendRGBA(base_bg, selected_tab_bg, vivid_mode and 0.65 or 0.35, 255))
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

local function GetAllOrderedPresets()
    local all = {}
    for _, name in ipairs(DARK_PRESET_ORDER) do all[#all + 1] = name end
    for _, name in ipairs(LIGHT_PRESET_ORDER) do all[#all + 1] = name end
    for _, name in ipairs(VIVID_PRESET_ORDER) do all[#all + 1] = name end
    for _, name in ipairs(GetCustomPresetNames()) do all[#all + 1] = name end
    return all
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
-- Central prev / next navigation buttons (all JKK windows)
-- Text is the safe default. Image mode can be enabled in Theme Manager.
-- Put future images at Modules/Icons/JKK_Nav_Left.png and
-- Modules/Icons/JKK_Nav_Right.png, or type an absolute PNG path.
-- If either image is missing/invalid, THAT button falls back to text.
----------------------------------------------------------
local NAV_TEXT_LEFT  = "◀"  -- single location for every left arrow's text
local NAV_TEXT_RIGHT = "▶"  -- single location for every right arrow's text
local NAV_DEFAULT_LEFT_PNG  = "Icons/JKK_Nav_Left.png"
local NAV_DEFAULT_RIGHT_PNG = "Icons/JKK_Nav_Right.png"
local NAV_REVISION_KEY = "nav_revision"

local nav_mode, nav_left_png, nav_right_png = "text", NAV_DEFAULT_LEFT_PNG, NAV_DEFAULT_RIGHT_PNG
local nav_last_revision = nil
local nav_image_cache = setmetatable({}, { __mode = "k" }) -- resource owned per ImGui context

local function LoadNavSettings(force)
    local revision = RPR.GetExtState(EXT_SECTION, NAV_REVISION_KEY)
    if not force and nav_last_revision == revision then return end
    nav_last_revision = revision
    nav_mode = (RPR.GetExtState(EXT_SECTION, "nav_mode") == "png") and "png" or "text"
    local left = RPR.GetExtState(EXT_SECTION, "nav_left_png")
    local right = RPR.GetExtState(EXT_SECTION, "nav_right_png")
    nav_left_png = left ~= "" and left or NAV_DEFAULT_LEFT_PNG
    nav_right_png = right ~= "" and right or NAV_DEFAULT_RIGHT_PNG
end

local function SaveNavSettings()
    RPR.SetExtState(EXT_SECTION, "nav_mode", nav_mode, true)
    RPR.SetExtState(EXT_SECTION, "nav_left_png", nav_left_png, true)
    RPR.SetExtState(EXT_SECTION, "nav_right_png", nav_right_png, true)
    nav_last_revision = tostring((tonumber(RPR.GetExtState(EXT_SECTION, NAV_REVISION_KEY)) or 0) + 1)
    RPR.SetExtState(EXT_SECTION, NAV_REVISION_KEY, nav_last_revision, true)
end

local function NavImagePath(path)
    if not path or path == "" then return nil end
    -- Windows absolute paths (C:\\...), UNC and POSIX absolute paths supported.
    if path:match("^%a:[/\\]") or path:match("^[/\\]") then return path end
    return core_dir .. path
end

local function NavImage(ctx, direction)
    if not (RPR.ImGui_CreateImage and RPR.ImGui_DrawList_AddImage and RPR.ImGui_Attach) then return nil end
    local path = NavImagePath(direction == "left" and nav_left_png or nav_right_png)
    if not path or not RPR.file_exists(path) then return nil end
    local cache = nav_image_cache[ctx]
    if not cache then cache = {}; nav_image_cache[ctx] = cache end
    local entry = cache[direction]
    if entry and entry.path == path and entry.image then
        if not RPR.ImGui_ValidatePtr or RPR.ImGui_ValidatePtr(entry.image, "ImGui_Image*") then
            return entry.image
        end
    end
    -- Create/attach to the current context only. ReaImGui resources are not
    -- interchangeable between distinct windows/contexts.
    local ok, resource = pcall(RPR.ImGui_CreateImage, path)
    if not ok or not resource then return nil end
    if not pcall(RPR.ImGui_Attach, ctx, resource) then return nil end
    cache[direction] = { path = path, image = resource }
    return resource
end

local function NavButton(ctx, id, direction, width, height)
    LoadNavSettings(false)
    local is_left = direction == "left" or direction == -1 or direction == "prev"
    direction = is_left and "left" or "right"
    -- Pass a unique hidden ID, not visible arrow glyphs, at each call site.
    id = tostring(id or "##JKK_Nav")
    if nav_mode == "png" then
        local image = NavImage(ctx, direction)
        if image and RPR.ImGui_GetItemRectMin and RPR.ImGui_GetItemRectMax then
            -- Draw on a NORMAL ImGui_Button so dimensions, theme states,
            -- disabled behavior and existing IDs are identical in both modes.
            local clicked = RPR.ImGui_Button(ctx, id, width or 0, height or 0)
            local min_x, min_y = RPR.ImGui_GetItemRectMin(ctx)
            local max_x, max_y = RPR.ImGui_GetItemRectMax(ctx)
            local side = math.max(1, math.min(max_x - min_x, max_y - min_y) - 8)
            local center_x, center_y = (min_x + max_x) / 2, (min_y + max_y) / 2
            -- Center a SQUARE icon even in tall/rectangular buttons; no stretching.
            pcall(RPR.ImGui_DrawList_AddImage, RPR.ImGui_GetWindowDrawList(ctx), image,
                center_x - side / 2, center_y - side / 2,
                center_x + side / 2, center_y + side / 2)
            return clicked
        end
    end
    return RPR.ImGui_Button(ctx, (is_left and NAV_TEXT_LEFT or NAV_TEXT_RIGHT) .. id, width or 0, height or 0)
end

LoadNavSettings(true)

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
local RETIRED_PRESETS = {
    ["Ember Night"] = true, ["Rosewater"] = true,
    ["Harbor Slate"] = true, ["Lichen Stone"] = true,
    ["Terracotta Fog"] = true, ["Mulberry Smoke"] = true,
    ["Brass Workshop"] = true, ["Petrol Mist"] = true,
    ["Indigo Canvas"] = true,
}
local saved_preset = RPR.GetExtState(EXT_SECTION, "selected_preset")
local selected_preset = (saved_preset ~= "") and saved_preset or "Default Dark"
if RETIRED_PRESETS[selected_preset] then
    -- The named preset no longer exists: replace its obsolete color values
    -- with an existing preset, rather than leaving the unreadable medium scheme active.
    selected_preset = "Peach Sorbet"
    LoadPreset(selected_preset)
end
local new_preset_name = ""

local function CyclePreset(delta)
    local all = GetAllOrderedPresets()
    if #all == 0 then return end
    local cur_idx = 1
    for i, name in ipairs(all) do
        if name == selected_preset then
            cur_idx = i
            break
        end
    end
    local next_idx = ((cur_idx - 1 + delta) % #all) + 1
    selected_preset = all[next_idx]
    LoadPreset(selected_preset)
end

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

    local flags = RPR.ImGui_ColorEditFlags_NoInputs()
    local edit_rgb = (current_col >> 8) & 0x00FFFFFF
    local changed, new_rgb = RPR.ImGui_ColorEdit3(ctx, "##col_" .. key, edit_rgb, flags)
    if changed then
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

    RPR.ImGui_SetNextWindowSizeConstraints(editor_ctx, 400, 640, 9999, 9999)
    RPR.ImGui_SetNextWindowSize(editor_ctx, 420, 705, RPR.ImGui_Cond_FirstUseEver())

    local sp, cp = ApplyTheme(editor_ctx, 1.0)
    local visible, open_flag = RPR.ImGui_Begin(editor_ctx, "JKK Theme Manager", editor_open, WindowChrome.flags())

    if visible then
        PushFont(editor_ctx, 1.0, "base")
        if WindowChrome.header(editor_ctx, 'JKK Theme Manager', 'theme') then open_flag = false end
        local avail_w = RPR.ImGui_GetContentRegionAvail(editor_ctx)
        local spacing = 8
        local nav_btn_w = 24
        local nav_gap = 4
        local action_btn_w = 65
        local combined_save_w = action_btn_w * 2 + spacing
        local left_area_w = math.max(80, avail_w - combined_save_w - spacing)
        local combo_w = math.max(30, left_area_w - (nav_btn_w * 2 + nav_gap * 2))

        -- 1. Presets Section
        PushText(editor_ctx, "accent")
        RPR.ImGui_Text(editor_ctx, "Presets")
        PopText(editor_ctx)

        if NavButton(editor_ctx, "##PrevPreset", "left", nav_btn_w, 0) then
            CyclePreset(-1)
        end

        RPR.ImGui_SameLine(editor_ctx, 0, nav_gap)
        RPR.ImGui_SetNextItemWidth(editor_ctx, combo_w)
        -- All 21 built-in presets appear in Dark -> Light -> Vivid order.
        -- Numerous custom presets may still scroll rather than overflow the display.
        local preset_count = #DARK_PRESET_ORDER + #LIGHT_PRESET_ORDER
            + #VIVID_PRESET_ORDER + #GetCustomPresetNames()
        local item_line_h = RPR.ImGui_GetTextLineHeightWithSpacing(editor_ctx)
        local popup_height = math.min(650, (preset_count + 3) * item_line_h + 24)
        RPR.ImGui_SetNextWindowSizeConstraints(editor_ctx,
            math.max(180, combo_w), popup_height, 16384, 16384)
        if RPR.ImGui_BeginCombo(
            editor_ctx, "##PresetCombo", selected_preset,
            RPR.ImGui_ComboFlags_HeightLargest()
        ) then
            RPR.ImGui_SeparatorText(editor_ctx, "DARK")
            for _, bname in ipairs(DARK_PRESET_ORDER) do
                if RPR.ImGui_Selectable(editor_ctx, bname, selected_preset == bname) then
                    selected_preset = bname; LoadPreset(bname)
                end
            end

            RPR.ImGui_SeparatorText(editor_ctx, "LIGHT")
            for _, bname in ipairs(LIGHT_PRESET_ORDER) do
                if RPR.ImGui_Selectable(editor_ctx, bname, selected_preset == bname) then
                    selected_preset = bname; LoadPreset(bname)
                end
            end

            RPR.ImGui_SeparatorText(editor_ctx, "VIVID")
            for _, bname in ipairs(VIVID_PRESET_ORDER) do
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

        RPR.ImGui_SameLine(editor_ctx, 0, nav_gap)
        if NavButton(editor_ctx, "##NextPreset", "right", nav_btn_w, 0) then
            CyclePreset(1)
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

        RPR.ImGui_SetNextItemWidth(editor_ctx, left_area_w)
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

        -- Shared navigation icon style: independent from color presets.
        PushText(editor_ctx, "accent")
        RPR.ImGui_Text(editor_ctx, "Navigation Buttons (Prev / Next)")
        PopText(editor_ctx)
        LoadNavSettings(false)
        RPR.ImGui_SetNextItemWidth(editor_ctx, math.max(100, avail_w - 70))
        if RPR.ImGui_BeginCombo(editor_ctx, "##NavButtonMode", nav_mode == "png" and "PNG images" or "Text arrows") then
            if RPR.ImGui_Selectable(editor_ctx, "Text arrows", nav_mode == "text") then
                nav_mode = "text"; SaveNavSettings()
            end
            if RPR.ImGui_Selectable(editor_ctx, "PNG images", nav_mode == "png") then
                nav_mode = "png"; SaveNavSettings()
            end
            RPR.ImGui_EndCombo(editor_ctx)
        end
        RPR.ImGui_SameLine(editor_ctx)
        NavButton(editor_ctx, "##NavPreviewLeft", "left", 24, 0)
        RPR.ImGui_SameLine(editor_ctx, 0, 4)
        NavButton(editor_ctx, "##NavPreviewRight", "right", 24, 0)
        if nav_mode == "png" then
            RPR.ImGui_SetNextItemWidth(editor_ctx, -1)
            local left_changed, left_value = RPR.ImGui_InputText(editor_ctx, "##NavLeftPng", nav_left_png)
            if left_changed then nav_left_png = left_value; SaveNavSettings() end
            if RPR.ImGui_IsItemHovered(editor_ctx) then RPR.ImGui_SetTooltip(editor_ctx, "Left arrow PNG. Relative to Modules/ or absolute path") end
            RPR.ImGui_SetNextItemWidth(editor_ctx, -1)
            local right_changed, right_value = RPR.ImGui_InputText(editor_ctx, "##NavRightPng", nav_right_png)
            if right_changed then nav_right_png = right_value; SaveNavSettings() end
            if RPR.ImGui_IsItemHovered(editor_ctx) then RPR.ImGui_SetTooltip(editor_ctx, "Right arrow PNG. Relative to Modules/ or absolute path") end
            RPR.ImGui_TextDisabled(editor_ctx, "Missing PNG = text fallback  |  Left, then Right")
        end

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

        -- 5. Bottom buttons: stay flush with the content area's bottom,
        -- regardless of theme-manager window height. If content is taller
        -- than the window, keep normal document flow/scrolling.
        local current_y = RPR.ImGui_GetCursorPosY(editor_ctx)
        local _, remain_h = RPR.ImGui_GetContentRegionAvail(editor_ctx)
        local _, item_gap_y = RPR.ImGui_GetStyleVar(editor_ctx, RPR.ImGui_StyleVar_ItemSpacing())
        local button_block_h = 24 + 26 + (item_gap_y or 8) * 2 + 3
        RPR.ImGui_SetCursorPosY(editor_ctx, math.max(current_y, current_y + remain_h - button_block_h))
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

        RPR.ImGui_Dummy(editor_ctx, 1, 3)
        if RPR.ImGui_Button(editor_ctx, "Reset All to Default", -1, 26) then
            ResetToDefaults()
            selected_preset = "Default Dark"
            RPR.SetExtState(EXT_SECTION, "selected_preset", "Default Dark", true)
        end

        PopFont(editor_ctx)

        if not RPR.ImGui_IsAnyItemActive(editor_ctx) and RPR.ImGui_IsKeyPressed(editor_ctx, RPR.ImGui_Key_Space(), false) then
            RPR.Main_OnCommand(40044, 0)
        end        
    end

    -- Escape closes the Theme Manager, but not while editing an input field
    -- or while a popup owns keyboard focus. This preserves Combo Escape behavior.
    if visible
        and RPR.ImGui_IsWindowFocused(editor_ctx, RPR.ImGui_FocusedFlags_RootWindow())
        and not RPR.ImGui_IsAnyItemActive(editor_ctx)
        and RPR.ImGui_IsKeyPressed(editor_ctx, RPR.ImGui_Key_Escape()) then
        open_flag = false
    end

    RPR.ImGui_End(editor_ctx)
    RPR.ImGui_PopStyleVar(editor_ctx, sp)
    RPR.ImGui_PopStyleColor(editor_ctx, cp)

    editor_open = open_flag
    if editor_open then
        RPR.defer(EditorLoop)
    else
        if editor_ctx and RPR.ImGui_DestroyContext then RPR.ImGui_DestroyContext(editor_ctx) end
        editor_ctx = nil
    end
end

local function OpenEditor()
    if editor_open and editor_ctx then
        if RPR.ImGui_SetWindowFocus then
            RPR.ImGui_SetWindowFocus(editor_ctx)
        end
        return
    end
    saved_preset = RPR.GetExtState(EXT_SECTION, "selected_preset")
    if saved_preset ~= "" then selected_preset = saved_preset end
    if RETIRED_PRESETS[selected_preset] then
        selected_preset = "Peach Sorbet"
        LoadPreset(selected_preset)
    end
    editor_ctx = RPR.ImGui_CreateContext("JKK_Theme_Manager")
    editor_open = true
    RPR.defer(EditorLoop)
end

local function GetColorRGBA(role)
    LoadConfig(false)
    local col = GetColor(role)
    if RPR.ImGui_ColorConvertU32ToDouble4 then
        return RPR.ImGui_ColorConvertU32ToDouble4(col)
    end
    local r = ((col >> 24) & 0xFF) / 255.0
    local g = ((col >> 16) & 0xFF) / 255.0
    local b = ((col >> 8)  & 0xFF) / 255.0
    local a = (col & 0xFF) / 255.0
    return r, g, b, a
end

local Theme = {
    ApplyTheme = ApplyTheme,
    PushButton = PushButton,
    PopButton = PopButton,
    PushText = PushText,
    PopText = PopText,
    PushFont = PushFont,
    PopFont = PopFont,
    GetColor = GetColor,
    GetColorRGBA = GetColorRGBA,
    GetRevision = GetRevision,
    NavButton = NavButton,
    GetSplitterColor = GetSplitterColor,
    OpenEditor = OpenEditor,
    ResetToDefaults = ResetToDefaults,
}
_G.JKK_Theme = Theme

return Theme