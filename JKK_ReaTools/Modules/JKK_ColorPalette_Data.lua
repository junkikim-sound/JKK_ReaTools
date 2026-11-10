--========================================================
-- @title JKK_ColorPalette_Data
-- @author Junki Kim
-- @noindex
--========================================================

local data = {}
local ext_section = "JKK_ColorPalette_Data"
local ext_key = "UserPalettes"

-- [수정됨] 각 테마의 고유성을 살리되, 기본 6원색(Red, Blue, Yellow, Green, White, Black)을
-- 테마 분위기에 맞게 변형하여 모든 팔레트에 필수로 포함시켰습니다.
data.default_palettes = {
    { name = "Warm", colors = {
        0xFF3B30FF, 0xFF5722FF, 0xFF9500FF, 0xFFCC00FF, 0xFFEB3BFF, 0xFBC02DFF, 0x8BC34AFF, 0x4CAF50FF,
        0x388E3CFF, 0x009688FF, 0x006064FF, 0x3F51B5FF, 0xFAFAFAFF, 0xFFF8E7FF, 0xE0E0E0FF, 0x9E9E9EFF,
        0x795548FF, 0x4E342EFF, 0xE64A19FF, 0xBF360CFF, 0xF44336FF, 0x212121FF, 0x111111FF, 0x000000FF
    }},
    { name = "Cool", colors = {
        0xE91E63FF, 0xC2185BFF, 0x880E4FFF, 0xFFEB3BFF, 0xCDDC39FF, 0xAFB42BFF, 0x00BCD4FF, 0x00E5FFFF,
        0x18FFFFFF, 0x009688FF, 0x004D40FF, 0x007AFFFF, 0x5AC8FAFF, 0x03A9F4FF, 0x0288D1FF, 0x01579BFF,
        0xFFFFFFFF, 0xF5F5F5FF, 0xCFD8DCFF, 0x90A4AEFF, 0x546E7AFF, 0x263238FF, 0x111111FF, 0x000000FF
    }},
    { name = "Dark", colors = {
        0x8B0000FF, 0x5C0000FF, 0xB71C1CFF, 0x827717FF, 0xF57F17FF, 0xE65100FF, 0x004D00FF, 0x1B5E20FF,
        0x33691EFF, 0x00008BFF, 0x1A237EFF, 0x01579BFF, 0x4A148CFF, 0x311B92FF, 0x004D40FF, 0x3E2723FF,
        0xE0E0E0FF, 0xBDBDBDFF, 0x3D3D3DFF, 0x2C2C2CFF, 0x212121FF, 0x1E1E1EFF, 0x121212FF, 0x000000FF
    }},
    { name = "Pastel", colors = {
        0xFFB3BAFF, 0xFFC0CBFF, 0xF48FB1FF, 0xFFFFBAFF, 0xFFDFBAFF, 0xFFE082FF, 0xBAFFC9FF, 0xA5D6A7FF,
        0x80CBC4FF, 0xBAE1FFFF, 0x90CAF9FF, 0x81D4FAFF, 0xE1BEE7FF, 0xD1C4E9FF, 0xB2DFDBFF, 0xF8BBD0FF,
        0xFFFFFFFF, 0xFAFAFAFF, 0xE0F7FAFF, 0xFFF9C4FF, 0xDCEDC8FF, 0xCFD8DCFF, 0x616161FF, 0x424242FF
    }},
    { name = "Neon", colors = {
        0xFF0000FF, 0xFF073AFF, 0xFF1493FF, 0xFFFF00FF, 0xFFEA00FF, 0xFFD300FF, 0x00FF00FF, 0x39FF14FF,
        0x00FA9AFF, 0x0000FFFF, 0x00FFFFFF, 0x08E8DEFF, 0xFF00FFFF, 0x8A2BE2FF, 0xFF4500FF, 0x7FFF00FF,
        0x1E90FFFF, 0x00FF7FFF, 0xFC0FC0FF, 0xFFFFFFFF, 0xF4F4F4FF, 0x222222FF, 0x0F0F0FFF, 0x000000FF
    }},
    { name = "Earth", colors = {
        0xCD5C5CFF, 0xA0522DFF, 0x8B4513FF, 0xDAA520FF, 0xB8860BFF, 0xCD853FFF, 0x8FBC8FFF, 0x6B8E23FF,
        0x556B2FFF, 0x778899FF, 0x5F9EA0FF, 0x4682B4FF, 0xFFE4C4FF, 0xF5DEB3FF, 0xEEE8AAFF, 0xDEB887FF,
        0xD2B48CFF, 0x3E2723FF, 0x4E342EFF, 0x1A1110FF, 0x2F4F4FFF, 0x151515FF, 0x0A0A0AFF, 0x000000FF
    }},
    { name = "Ocean", colors = {
        0xFF7F50FF, 0xFF6347FF, 0xE9967AFF, 0xFFD700FF, 0xF4A460FF, 0xEEE8AAFF, 0x00FA9AFF, 0x48D1CCFF,
        0x20B2AAFF, 0x2E8B57FF, 0x006400FF, 0x00BFFFFF, 0x1E90FFFF, 0x4169E1FF, 0x0000CDFF, 0x000080FF,
        0xFFFFFFFF, 0xF0F8FFFF, 0xE0FFFFFF, 0x2F4F4FFF, 0x191970FF, 0x0A0A0AFF, 0x000033FF, 0x000000FF
    }},
    { name = "Sunset", colors = {
        0xDC143CFF, 0xFF4500FF, 0x800080FF, 0x8B008BFF, 0x9932CCFF, 0xFF8C00FF, 0xFFA500FF, 0xFFD700FF,
        0xFFFFE0FF, 0x3CB371FF, 0x228B22FF, 0x008080FF, 0x4169E1FF, 0x483D8BFF, 0x00008BFF, 0xFFFFFFFF,
        0xFFFAFAFF, 0xFFF5EEFF, 0x362142FF, 0x2F2F4FFF, 0x19192AFF, 0x1A1A1AFF, 0x0B0B0BFF, 0x000000FF
    }},
    { name = "Forest", colors = {
        0xCD5C5CFF, 0xB22222FF, 0x8B0000FF, 0xFAFAD2FF, 0xFFD700FF, 0xBDB76BFF, 0x9ACD32FF, 0x32CD32FF,
        0x228B22FF, 0x008000FF, 0x006400FF, 0x5F9EA0FF, 0x4682B4FF, 0x1E90FFFF, 0xFFFFFFFF, 0xFFFAFAFF,
        0xF5F5DCFF, 0xA0522DFF, 0x8B4513FF, 0x2F4F4FFF, 0x1C1C1CFF, 0x111111FF, 0x080808FF, 0x000000FF
    }},
    { name = "Grayscale", colors = {
        0xFF0000FF, 0x8B0000FF, 0xFF5252FF, 0xFFFF00FF, 0xFFAB00FF, 0xFDD835FF, 0x00FF00FF, 0x00E676FF,
        0x006400FF, 0x0000FFFF, 0x448AFFFF, 0x00008BFF, 0xFFFFFFFF, 0xFAFAFAFF, 0xE0E0E0FF, 0xC0C0C0FF,
        0xA0A0A0FF, 0x808080FF, 0x606060FF, 0x404040FF, 0x202020FF, 0x121212FF, 0x050505FF, 0x000000FF
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