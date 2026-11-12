-- Translations go into EllesmereUI's own catalog, which its widgets read whenever they show text, so the settings,
-- tooltips and messages follow eUI's language (the client's, or its own language override). Keys are the English
-- text the code writes. On a key eUI already translates, eUI's wording wins, so shared terms read the same everywhere.
local _, ns = ...
local EUI = _G.EllesmereUI

local mine = {}   -- keys this add-on filled, which the game's own names may still replace

-- Returns a table taking `code`'s translations, or nil when eUI shows another language.
-- esMX reads esES as eUI does; eUI merged its own fallback before this add-on loaded, so esES entries go straight in.
function ns.Locale(code)
    local active = EUI.LOCALE
    local catalog = (active == code or (active == "esMX" and code == "esES")) and EUI.RegisterLocale(active)
    if not catalog then return nil end
    return setmetatable({}, { __newindex = function(_, key, text)
        if catalog[key] == nil then
            catalog[key] = text
            mine[key] = true
        end
    end })
end

-- Poison and Flash Powder names come from the game when eUI shows the client's own language: each poison's first
-- recipe spell carries its name, and Flash Powder is an item. They replace a locale file's guess but not eUI's own
-- name. With eUI in another language than the client, the game's names would be in the wrong one, so they are skipped.
local function Language(code) return code == "esMX" and "esES" or code end
local active = EUI.LOCALE
if active ~= "enUS" and Language(active) == Language(GetLocale()) then
    local catalog = EUI.RegisterLocale(active)
    if catalog then
        local function Fill(key, text)
            if text and (catalog[key] == nil or mine[key]) then catalog[key] = text end
        end
        -- The first ranks of Restock.lua's RECIPE_SPELLS, which only loads for rogues.
        local recipes = { ["Instant Poison"] = 8681, ["Deadly Poison"] = 2835, ["Crippling Poison"] = 3420,
            ["Mind-numbing Poison"] = 5763, ["Wound Poison"] = 13220 }
        for name, spell in pairs(recipes) do Fill(name, C_Spell.GetSpellName(spell)) end
        local flash = Item:CreateFromItemID(5140)
        flash:ContinueOnItemLoad(function() Fill("Flash Powder", flash:GetItemName()) end)
    end
end
