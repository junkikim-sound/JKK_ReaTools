--========================================================
-- @title JKK_ColorPalette_Data
-- @author Junki Kim
-- @noindex
--========================================================

local data = {}
local ext_section = "JKK_ColorPalette_Data"
local ext_key = "UserPalettes"

-- 10 curated palettes for DAW color coding.
-- Colors use 0xRRGGBBAA format with full opacity (FF).
-- Every preset contains 24 distinct colors with a consistent tone
-- while keeping enough hue and value contrast for quick identification.
data.default_palettes = {
    -- Balanced, versatile colors for everyday use.
    { name = "Default", colors = {
        0xE65B55FF, 0xE97945FF, 0xDDA13FFF, 0xE5C64AFF, 0xA9C94DFF, 0x6FBF54FF,
        0x42AE68FF, 0x39B99AFF, 0x36B8B4FF, 0x42B6D6FF, 0x519BD7FF, 0x4E7FD1FF,
        0x625EC5FF, 0x835BCCFF, 0xA85CC3FF, 0xCE59B5FF, 0xE36F9FFF, 0xD94F78FF,
        0xBD4C5AFF, 0xB9684BFF, 0x9C9A49FF, 0x6D9A73FF, 0x668EA5FF, 0x8485B7FF
    }},

    -- Warm citrus colors with fresh green and cool accent colors.
    { name = "Citrus Pop", colors = {
        0xE85C3FFF, 0xF07832FF, 0xF47F2CFF, 0xF4A340FF, 0xE6B632FF, 0xF0CF3EFF,
        0xDCE64AFF, 0xB8D548FF, 0x8DC449FF, 0x64B65BFF, 0x3EA77AFF, 0x31B6A0FF,
        0x45C7C9FF, 0x53B4E0FF, 0x4478C7FF, 0x7555C8FF, 0xAD55BBFF, 0xD45A9BFF,
        0xD84A68FF, 0xA9474CFF, 0xA95F38FF, 0xB78D36FF, 0x879B3FFF, 0xE8A76AFF
    }},

    -- Deep sea greens and blues balanced by coral and sandy highlights.
    { name = "Deep Ocean", colors = {
        0x287F79FF, 0x329A91FF, 0x3CB7A4FF, 0x66C8B6FF, 0x4AB6C9FF, 0x3F9FCEFF,
        0x367FB9FF, 0x3563A8FF, 0x4A55A8FF, 0x6555B8FF, 0x8063C7FF, 0xA16BC7FF,
        0xC16DAFFF, 0xD56D86FF, 0xD66D59FF, 0xE5A35EFF, 0xD6BF6AFF, 0x9FC47AFF,
        0x6CA982FF, 0x4A8F86FF, 0x3B738AFF, 0x6296ADFF, 0x87A7B8FF, 0x647D9CFF
    }},

    -- Botanical greens, foliage tones, and colorful flower accents.
    { name = "Wild Garden", colors = {
        0xD75F57FF, 0xE58A55FF, 0xE0BC53FF, 0xD3D65AFF, 0xA7C957FF, 0x79B75AFF,
        0x4DAB68FF, 0x399B70FF, 0x3EAE8FFF, 0x69C1A7FF, 0x82C7B4FF, 0x78B99BFF,
        0x5F9C62FF, 0x7A8F49FF, 0xA2A45CFF, 0xB18A55FF, 0x9D674DFF, 0xC06D77FF,
        0xD16D9FFF, 0xB66CB5FF, 0x8B72C3FF, 0x6687BEFF, 0x4F9AB7FF, 0x78B5C9FF
    }},

    -- Sunset warmth fading into muted twilight blues and purples.
    { name = "Golden Hour", colors = {
        0xB9474DFF, 0xD24F45FF, 0xE46B3FFF, 0xEA853EFF, 0xE99F43FF, 0xD4AA3EFF,
        0xE5C45AFF, 0xC9B75AFF, 0xA6A04EFF, 0x778B54FF, 0x5D8E70FF, 0x4E99A1FF,
        0x5889B8FF, 0x6574B6FF, 0x7964B7FF, 0x9A64B6FF, 0xB85F9DFF, 0xD16387FF,
        0xE77D78FF, 0xE8A19AFF, 0xC78B75FF, 0xA76D5EFF, 0xD19B68FF, 0xE3C58AFF
    }},

    -- High-energy neon colors for maximum visual separation.
    { name = "Neon Arcade", colors = {
        0xFF3A48FF, 0xFF5A1FFF, 0xFF8A00FF, 0xFFD400FF, 0xC9FF00FF, 0x7CFF00FF,
        0x2DFF3EFF, 0x00E878FF, 0x00F5B8FF, 0x00EDEBFF, 0x00C7FFFF, 0x238BFFFF,
        0x3658FFFF, 0x693BFFFF, 0x9C2EFFFF, 0xD12DFFFF, 0xFF2ED1FF, 0xFF2E91FF,
        0xF70067FF, 0xB7FF3CFF, 0x42FFB0FF, 0x35B9FFFF, 0xA13BFFFF, 0xFF884DFF
    }},

    -- Light, soft colors with enough saturation to remain distinguishable.
    { name = "Soft Pastel", colors = {
        0xE89B9BFF, 0xF1B38FFF, 0xF1CA8DFF, 0xE9D78FFF, 0xD6E39AFF, 0xB6D99AFF,
        0x9CD6A5FF, 0x8FD4B8FF, 0x8ED5CDFF, 0x91CFDFFF, 0x9BBFE7FF, 0xA7A9E4FF,
        0xB7A2E4FF, 0xCBA0E0FF, 0xE0A0D5FF, 0xE9A0BDFF, 0xD98FB0FF, 0xC5A3A0FF,
        0xBCC8AAFF, 0xA8C5C4FF, 0xAAB6C9FF, 0xB8B2C8FF, 0xCBB9A0FF, 0xE5B0A5FF
    }},

    -- Muted analog-film colors: faded reds, ochres, greens, and dusty blues.
    { name = "Retro Film", colors = {
        0xB65B50FF, 0xC87557FF, 0xC18B58FF, 0xBFA45BFF, 0xB9B46AFF, 0x8E9E5DFF,
        0x6D9568FF, 0x5C8D77FF, 0x4F8D88FF, 0x5E9BA1FF, 0x668CA4FF, 0x65799BFF,
        0x7776A2FF, 0x92709BFF, 0xA66F91FF, 0xBD7488FF, 0xCF8B81FF, 0xBBA18BFF,
        0x8B786CFF, 0x786D60FF, 0x7A866FFF, 0x6F827FFF, 0xA0A69BFF, 0xC0B6A2FF
    }},

    -- Rich gemstone colors: ruby, topaz, emerald, sapphire, and amethyst.
    { name = "Midnight Jewel", colors = {
        0xA83245FF, 0xD04A57FF, 0xB85B37FF, 0xC28A35FF, 0xA6A72EFF, 0x6E9F45FF,
        0x2D9972FF, 0x277F86FF, 0x2777A6FF, 0x3153A2FF, 0x4647A2FF, 0x6446A6FF,
        0x8B4EA8FF, 0xB04D9EFF, 0xD34E82FF, 0xD26F4DFF, 0x7D553AFF, 0x9C713EFF,
        0x606A42FF, 0x4B6C5AFF, 0x3F657DFF, 0x5E5C85FF, 0x865B72FF, 0xB07980FF
    }},

    -- Natural clay, soil, stone, dry grasses, and weathered foliage.
    { name = "Earth & Clay", colors = {
        0xAF5145FF, 0xC36B4CFF, 0xD58A54FF, 0xC99E5BFF, 0xD0B76BFF, 0xA99C52FF,
        0x7F8D4DFF, 0x668B58FF, 0x5D876DFF, 0x6A9A8AFF, 0x5A9AA0FF, 0x59869AFF,
        0x55728AFF, 0x6C6E8AFF, 0x87718CFF, 0xA16D79FF, 0x8E5A4BFF, 0x76513DFF,
        0x9D765BFF, 0xB38A6BFF, 0x8C8A72FF, 0x747D78FF, 0xA0A6A0FF, 0xC4B39AFF
    }}
}

function data.LoadUserPalettes()
    local user_palettes = {}
    local ext_str = reaper.GetExtState(ext_section, ext_key)
    if ext_str and ext_str ~= "" then
        for block in string.gmatch(ext_str, "([^;]+)") do
            local name, colors_str = string.match(block, "([^|]+)|([^|]+)")
            if name and colors_str then
                local p = { name = name, colors = {} }
                for col in string.gmatch(colors_str, "([^,]+)") do
                    table.insert(p.colors, tonumber(col))
                end
                table.insert(user_palettes, p)
            end
        end
    end
    return user_palettes
end

function data.SaveUserPalettes(user_palettes)
    local save_str = ""
    for _, p in ipairs(user_palettes) do
        local c_str = table.concat(p.colors, ",")
        save_str = save_str .. p.name .. "|" .. c_str .. ";"
    end
    reaper.SetExtState(ext_section, ext_key, save_str, true)
end

return data
