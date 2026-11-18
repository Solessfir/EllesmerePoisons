-- The add-on's page in the game's Options > AddOns, with or without EllesmereUI.
-- It covers what the game's controls can show: the type and button editors' drag order, the custom icon's name
-- and color alpha stay on the eUI page. Values changed elsewhere while it is open show once its page is reopened.
local ADDON, ns = ...
local L = ns.EUI.L

local count = 0   -- every setting needs a unique variable name

-- Controls added in order to `category`'s list. `shown`, when given, hides a control until it returns true.
-- Every row goes in through Settings.RegisterInitializer, which adds it from Blizzard's secure delegate. Rows added
-- from add-on code (Settings.CreateCheckbox and the like) taint the settings search, and a restricted button in its
-- results is then blocked and blamed on this add-on.
local function Builder(category)
    local B = {}

    local function Register(text, varType, default, get, set)
        count = count + 1
        return Settings.RegisterProxySetting(category, ADDON .. "Option" .. count, varType, L(text), default, get, set)
    end

    local function Add(init, shown)
        if shown then init:AddShownPredicate(shown) end
        Settings.RegisterInitializer(category, init)
        return init
    end

    function B.Header(text)
        Add(CreateSettingsListSectionHeaderInitializer(L(text)))
    end

    function B.Toggle(text, get, set, default, tip, shown)
        local s = Register(text, Settings.VarType.Boolean, default, get, set)
        return Add(Settings.CreateCheckboxInitializer(s, nil, tip and L(tip)), shown)
    end

    local function AddSlider(s, min, max, step, format, tip, shown)
        local options = Settings.CreateSliderOptions(min, max, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
        return Add(Settings.CreateSliderInitializer(s, options, tip and L(tip)), shown)
    end

    function B.Slider(text, get, set, default, min, max, step, tip, shown)
        local s = Register(text, Settings.VarType.Number, default, get, set)
        local format = step < 1 and "%.2f" or "%d"
        return AddSlider(s, min, max, step, function(v) return format:format(v) end, tip, shown)
    end

    -- A stepped slider naming the choice: Forever's native settings dropdown hits a menu VM assertion.
    -- `order` may hold "---" separators (eUI's dropdowns). A saved value the list lacks (an eUI-only shape after
    -- eUI is gone) reads as `fallback`, the choice it is drawn like.
    function B.Dropdown(text, get, set, default, values, order, tip, shown, fallback)
        local list = {}
        for _, v in ipairs(order) do
            if v ~= "---" then list[#list + 1] = v end
        end
        local function Index(v) return tIndexOf(list, v) end
        local s = Register(text, Settings.VarType.Number, Index(default) or 1,
            function() return Index(get()) or Index(fallback) or Index(default) or 1 end,
            function(i) if list[i] then set(list[i]) end end)
        return AddSlider(s, 1, #list, 1, function(i) return L(values[list[i]] or "") end, tip, shown)
    end

    -- The game's swatch picks red, green and blue only (its values carry alpha 0), so a saved alpha is kept, except
    -- that picking the default color, as Defaults does, also brings back the default alpha. The value carries the
    -- alpha so Defaults still counts as a change when only the alpha differs.
    function B.Color(text, get, set, default, tip, shown)
        local function Hex(c, a) return CreateColor(c.r, c.g, c.b, a or c.a or 1):GenerateHexColor() end
        local s = Register(text, Settings.VarType.String, Hex(default),
            function() return Hex(get()) end,
            function(v)
                local c = CreateColorFromHexString(v)
                local a = Hex(c, 1) == Hex(default, 1) and default.a or get().a
                set({ r = c.r, g = c.g, b = c.b, a = a })
            end)
        return Add(Settings.CreateColorSwatchInitializer(s, nil, tip and L(tip)), shown)
    end

    function B.Button(text, onClick, tip)
        Add(CreateSettingsButtonInitializer(L(text), L(text), onClick, tip and L(tip), true))
    end

    return B
end

local function DockPage(category)
    local D = ns.Dock
    local Get, Set, DEF = D.Get, D.Set, D.DEFAULTS
    local B = Builder(category)
    local function Toggle(text, key, tip, shown)
        return B.Toggle(text, function() return Get(key) end, function(v) Set(key, v) end, DEF[key], tip, shown)
    end
    local function Slider(text, key, min, max, step, tip, shown)
        return B.Slider(text, function() return Get(key) end, function(v) Set(key, v) end, DEF[key], min, max, step or 1,
            tip, shown)
    end
    local function Dropdown(text, key, values, order, tip, shown, fallback)
        return B.Dropdown(text, function() return Get(key) end, function(v) Set(key, v) end, DEF[key], values, order,
            tip, shown, fallback)
    end
    local function Color(text, key, tip, shown)
        return B.Color(text, function() return Get(key) end, function(v) Set(key, v) end, DEF[key], tip, shown)
    end

    B.Header("General")
    Toggle("Enable", "enabled", ns.standalone and "Shows the dock. Shift-drag the button to move it."
        or "Shows the dock. Move it in EllesmereUI's Unlock Mode.")
    Toggle("Hide When None in Bags", "hideEmpty", "Hides the button while you carry no poisons, stones or oils.")
    Toggle("Highest Rank Only", "highestOnly", "Shows one icon per type: the best rank you carry.")
    Dropdown("Tooltips", "tooltip", D.TOOLTIPS, D.TOOLTIP_ORDER, "Full: the item's tooltip. Name Only: just the item's name.")
    -- ApplyShape draws a shape without eUI's art like None.
    Dropdown("Icon Shape", "shape", D.SHAPES, D.SHAPE_ORDER, "The shape of the button and every flyout icon.", nil, "none")
    B.Button("Reset Position", ns.ResetPosition)

    B.Header("Poisons, Stones and Oils")
    local rogue = ns.Restock ~= nil
    for _, g in ipairs(D.GROUPS) do
        if rogue or g.kind ~= "poison" then
            B.Toggle(g.name, function() return not D.IsHidden(g) end, function(v) D.SetHidden(g.name, not v) end, true)
        end
    end

    B.Header("Button")
    Dropdown("Button Icon", "mainIcon", D.MAIN_ICONS, D.MAIN_ICON_ORDER,
        "Last Applied shows whatever you last put on a weapon.")
    Slider("Button Size", "size", D.SIZE_MIN, D.SIZE_MAX)
    Slider("Opacity", "opacity", 0.1, 1, 0.05, "Opacity of the button and flyout. Show Only on Mouseover fades up to this value.")
    Toggle("Show Only on Mouseover", "mouseover", "Keeps the button invisible until the mouse is over it.")

    B.Header("Flyout")
    Dropdown("Flyout Direction", "direction", D.DIRECTIONS, D.DIRECTION_ORDER)
    Slider("Item Size", "itemSize", 16, 64)
    Slider("Spacing", "spacing", 0, 10)
    Toggle("Flyout Background", "background", "Draws a themed panel behind the flyout's icons.")

    B.Header("Behavior")
    Dropdown("Open On", "openMode", D.OPEN_MODES, D.OPEN_MODE_ORDER)
    Dropdown("After a Click", "clickClose", D.CLICK_CLOSES, D.CLICK_CLOSE_ORDER,
        "Stay Open: click the button again to close. Hide After Leaving: closes once the mouse leaves.",
        function() return Get("openMode") == "click" end)
    Slider("Open Delay (sec)", "openDelay", 0, 1, 0.05, nil, function() return Get("openMode") == "hover" end)
    Slider("Hide Delay (sec)", "closeDelay", 0, 2, 0.05, nil,
        function() return not (Get("openMode") == "click" and Get("clickClose") == "stay") end)
    Toggle("Close After Use", "closeOnUse", "Closes the flyout once you apply something.")

    B.Header("Animation")
    local animated = function() return Get("animation") ~= "instant" end
    Dropdown("Animation", "animation", D.ANIMATIONS, D.ANIMATION_ORDER)
    Dropdown("Easing", "easing", D.EASING_NAMES, D.EASING_ORDER, nil, animated)
    Slider("Duration (sec)", "duration", 0.05, 0.6, 0.05, nil, animated)
    Slider("Cascade Delay (sec)", "stagger", 0.01, 0.2, 0.01, "How long each icon waits after the one before it.",
        function() return Get("animation") == "cascade" end)

    B.Header("Highlight Applied")
    local glowOn = function() return Get("applied") end
    Toggle("Highlight Applied", "applied", "Makes whatever is on your weapons glow in the open flyout.")
    Color("Highlight Color", "glowColor", nil, glowOn)
    Dropdown("Highlight Animation", "glowStyle", D.GLOW_STYLES, D.GLOW_STYLE_ORDER, nil, glowOn)
    Slider("Pulse Speed (sec)", "glowSpeed", 0.2, 3, 0.1, "Seconds for each fade, out or back. Higher is slower.",
        function() return Get("applied") and Get("glowStyle") ~= "static" end)

    B.Header("Item Count")
    local countOn = function() return Get("showCount") end
    Toggle("Show Item Counts", "showCount")
    Dropdown("Count Position", "countPoint", D.COUNT_POINTS, D.COUNT_POINT_ORDER, nil, countOn)
    Slider("Count Size", "countSize", 6, 24, 1, nil, countOn)
    Dropdown("Count Outline", "countOutline", D.OUTLINES, D.OUTLINE_ORDER, nil, countOn)
    Slider("Count X Offset", "countX", -20, 20, 1, nil, countOn)
    Slider("Count Y Offset", "countY", -20, 20, 1, nil, countOn)
    Color("Count Color", "countColor", nil, countOn)

    B.Header("Effects")
    local fxOn = function() return Get("fx") end
    Toggle("Enable Effects", "fx")
    Toggle("Effects Only on Hover", "bubblesOnHover", "Bubbles and sparkles show only while the mouse is over the dock.", fxOn)
    Toggle("Effects Only When Applied", "bubblesOnApplied",
        "Bubbles show only while a poison is on a weapon, sparkles only while a stone or oil is.", fxOn)
    Dropdown("Applied On", "appliedHand", D.APPLIED_HANDS, D.APPLIED_HAND_ORDER,
        "Which weapon Effects Only When Applied looks at.", function() return Get("fx") and Get("bubblesOnApplied") end)
    Slider("Splash Opacity", "splashAlpha", 0, 1, 0.05,
        "Droplets bursting from the button when you apply something. 0 turns it off.", fxOn)
    Color("Bubbles Color", "bubbleColor", nil, fxOn)
    Color("Sparkles Color", "sparkleColor", nil, fxOn)
end

local function RestockPage(category)
    local R = ns.Restock
    local B = Builder(category)
    local function LookSlider(text, key, min, max, step, tip)
        return B.Slider(text, function() return R.Look(key) end, function(v) R.SetLook(key, v) end, R.LOOKS[key],
            min, max, step or 1, tip)
    end
    local function LookDropdown(text, key, values, order, tip, fallback)
        return B.Dropdown(text, function() return R.Look(key) end, function(v) R.SetLook(key, v) end, R.LOOKS[key],
            values, order, tip, nil, fallback)
    end
    local function LookColor(text, key, tip, shown)
        return B.Color(text, function() return R.Look(key) end, function(v) R.SetLook(key, v) end, R.LOOKS[key], tip, shown)
    end

    B.Header("Restock at Vendors")
    B.Toggle("Enable", R.IsOn, R.SetOn, true, "Shows restock buttons beside the merchant window at poison and reagent vendors.")
    B.Button("Reset Position", R.ResetPosition)

    B.Header("Buttons")
    for _, name in ipairs(R.TYPES) do
        B.Toggle(name, function() return not R.IsHidden(name) end, function(v) R.SetHidden(name, not v) end, true)
    end

    B.Header("Poison Targets")
    for _, name in ipairs(R.TYPES) do
        if name ~= R.FLASH then
            B.Slider(name, function() return R.Target(name) end, function(v) R.SetTarget(name, v) end, 0,
                0, R.MAX_TARGET, R.STEP, "How many to keep. Clicking it at a poison vendor restocks up to this.")
        end
    end
    B.Header("Reagent Targets")
    B.Slider(R.FLASH, function() return R.Target(R.FLASH) end, function(v) R.SetTarget(R.FLASH, v) end, 0,
        0, R.MAX_TARGET, R.STEP, "How many to keep. Clicking it at a vendor buys up to this.")

    B.Header("Layout")
    LookDropdown("Layout", "layout", R.LAYOUTS, R.LAYOUT_ORDER, "Vertical: a column. Horizontal: a row.")
    LookDropdown("Icon Shape", "shape", ns.Dock.SHAPES, ns.Dock.SHAPE_ORDER, nil, "none")
    LookSlider("Button Size", "size", 16, 64)
    LookSlider("Spacing", "spacing", 0, 10, 1, "Gap between the buttons.")
    B.Toggle("Background", function() return R.Look("background") end, function(v) R.SetLook("background", v) end,
        R.LOOKS.background, "Draws a themed panel behind the buttons.")

    B.Header("Numbers")
    LookSlider("Number Size", "countSize", 6, 24, 1, "The target (top left) and the count you have (bottom right).")
    LookDropdown("Number Outline", "countOutline", ns.Dock.OUTLINES, ns.Dock.OUTLINE_ORDER)
    LookColor("Target Color", "countColor", "The count you have stays red when short and green when stocked.")

    B.Header("Effects")
    B.Toggle("Crafting Effects", function() return R.Look("splash") end, function(v) R.SetLook("splash", v) end,
        R.LOOKS.splash, "Bubbles rise from a poison's button when its craft starts, and droplets burst for each poison made.")
    LookColor("Effects Color", "splashColor", nil, function() return R.Look("splash") end)
end

-- Called by EllesmerePoisons.lua at login, once the settings are loaded.
function ns.RegisterOptions()
    local category = Settings.RegisterVerticalLayoutCategory("Ellesmere Poisons")
    DockPage(category)
    ns.settingsCategories = { General = category:GetID() }
    if ns.Restock then
        local sub = Settings.RegisterVerticalLayoutSubcategory(category, L("Restock"))
        RestockPage(sub)
        ns.settingsCategories.Restock = sub:GetID()
    end
    Settings.RegisterAddOnCategory(category)
end
