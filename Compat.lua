-- EllesmereUI when it is installed, else a stand-in with the few parts the add-on reads from it.
-- Standalone, the dock keeps its plain look: no eUI skin, no masked shapes, Shift-drag instead of Unlock Mode,
-- and settings only in the game's Options > AddOns.
local _, ns = ...
if _G.EllesmereUI then
    ns.EUI = _G.EllesmereUI
    return
end
ns.standalone = true

local catalog = {}   -- the client language's translations, filled by the locale files
local function L(key) return catalog[key] or key end
local function Nop(...) end

ns.EUI = {
    LOCALE = GetLocale(),
    L = L,
    Lf = function(fmt, ...) return L(fmt):format(...) end,
    RegisterLocale = function(code) if code == GetLocale() then return catalog end end,
    SHAPE_MASKS = {}, SHAPE_BORDERS = {}, SHAPE_INSETS = {},
    IsUnlockModeActive = function() return false end,
    RefreshPage = Nop, RegisterPlugin = Nop, GetPluginModuleKey = Nop,
    -- Options.lua fills ns.settingsCategories once the panel is registered.
    OpenPlugin = function(_, page)
        local id = ns.settingsCategories and ns.settingsCategories[page or "General"]
        if id then Settings.OpenToCategory(id) end
    end,
}
