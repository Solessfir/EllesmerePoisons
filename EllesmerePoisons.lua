-- Ellesmere Poisons. The dock: one button that opens a flyout of the weapon buffs in your bags.
-- Left-click applies to the main hand, right-click to the off hand.
-- Styled through EllesmereUI's skinning API, moved in its Unlock Mode, configured on its plugin page.
local ADDON, ns = ...
local EUI = _G.EllesmereUI
-- eUI translates the text its widgets show; text set here goes through its translator by hand (see Localization.lua).
local L = EUI.L

-- Default order; items lowest rank first. Item IDs follow EllesmereUIAuraBuffReminders' EABR.FV_WEAPON_BUFFS.
-- ponytail: a hand-kept copy, since the module only exposes it as an underscore (internal) global.
-- This add-on avoids EllesmereUI internals beyond the one Element Options hook in RegisterUnlock.
-- Update both if Forever adds ranks.
-- The name doubles as the saved key for the custom order and hidden types.
local GROUPS = {
    { name = "Instant Poison", kind = "poison", 6947, 6949, 6950, 8926, 8927, 8928 },
    { name = "Deadly Poison", kind = "poison", 2892, 2893, 8984, 8985, 20844 },
    { name = "Crippling Poison", kind = "poison", 3775, 3776 },
    { name = "Mind-numbing Poison", kind = "poison", 5237, 6951, 9186 },
    { name = "Wound Poison", kind = "poison", 10918, 10920, 10921, 10922 },
    { name = "Sharpening Stone", kind = "stone", 2862, 287978, 2863, 2871, 7964, 12404 },
    { name = "Weightstone", kind = "stone", 3239, 3240, 3241, 7965, 12643 },
    { name = "Elemental Sharpening Stone", kind = "stone", 18262, 287980 },
    { name = "Wizard Oil", kind = "stone", 20744, 20746, 287979, 20750, 20749 },
    { name = "Mana Oil", kind = "stone", 20745, 20747, 20748 },
    { name = "Shadow Oil", kind = "stone", 3824 },
    { name = "Frost Oil", kind = "stone", 3829 },
    { name = "Blessed Wizard Oil", kind = "stone", 23123 },
    { name = "Consecrated Sharpening Stone", kind = "stone", 23122 },
}
local GROUP_BY_NAME, GROUP_OF_ITEM = {}, {}
for _, g in ipairs(GROUPS) do
    GROUP_BY_NAME[g.name] = g
    for i = 1, #g do GROUP_OF_ITEM[g[i]] = g end
end

local DEFAULTS = {
    enabled = true, size = 36, itemSize = 32, spacing = 2, direction = "LEFT",
    showCount = true, highestOnly = true, hideEmpty = false, shape = "cropped", tooltip = "full",
    background = false,
    openMode = "hover", clickClose = "stay", openDelay = 0, closeDelay = 0.3, closeOnUse = false,
    animation = "fadeslide", easing = "out", duration = 0.15,
    mainIcon = "brew", customIcon = "", mouseover = false, opacity = 1, stagger = 0.04,
    fx = true, bubbleColor = { r = 0.45, g = 1, b = 0.25, a = 0.9 }, splashAlpha = 0.9, bubblesOnHover = false, bubblesOnApplied = false, appliedHand = "any", applied = true,
    sparkleColor = { r = 1, g = 0.95, b = 0.75, a = 0.9 },
    glowStyle = "static", glowSpeed = 0.8,
    countSize = 11, countPoint = "BOTTOMRIGHT", countColor = { r = 1, g = 1, b = 1 },
    countOutline = "OUTLINE", countX = 0, countY = 0, glowColor = { r = 0.45, g = 1, b = 0.25, a = 0.8 },
}
local DIRECTIONS = { UP = "Up", DOWN = "Down", LEFT = "Left", RIGHT = "Right" }
local DIRECTION_ORDER = { "UP", "DOWN", "LEFT", "RIGHT" }
-- The shapes EllesmereUI's own icon pickers offer; masked ones use its shape art (EllesmereUI.SHAPE_MASKS).
local SHAPES = {
    none = "None", cropped = "Cropped", square = "Square", circle = "Circle", csquare = "Curved Square",
    diamond = "Diamond", hexagon = "Hexagon", portrait = "Portrait", shield = "Shield",
}
local SHAPE_ORDER = { "none", "cropped", "---", "square", "circle", "csquare", "diamond", "hexagon", "portrait", "shield" }
local COUNT_POINTS = {
    BOTTOMRIGHT = "Bottom Right", BOTTOMLEFT = "Bottom Left", BOTTOM = "Bottom", CENTER = "Center",
    TOPRIGHT = "Top Right", TOPLEFT = "Top Left", TOP = "Top",
}
local COUNT_POINT_ORDER = { "BOTTOMRIGHT", "BOTTOMLEFT", "BOTTOM", "CENTER", "TOPRIGHT", "TOPLEFT", "TOP" }
local COUNT_INSET = 2   -- count text distance from the icon's edge
local OUTLINES = { NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick Outline", SHADOW = "Drop Shadow" }
local OUTLINE_ORDER = { "NONE", "OUTLINE", "THICKOUTLINE", "SHADOW" }
local TOOLTIPS = { full = "Full", name = "Name Only", off = "Off" }
local APPLIED_HANDS = { any = "Any Weapon", main = "Main Hand Only" }
local APPLIED_HAND_ORDER = { "any", "main" }
local TOOLTIP_ORDER = { "full", "name", "off" }
local ZOOM = 0.07   -- trims the bevel baked into icon art
local SIZE_MIN, SIZE_MAX = 20, 64   -- Button Size range, shared by the slider and the Unlock Mode resize
local OPEN_MODES = { hover = "Hover", click = "Click" }
local OPEN_MODE_ORDER = { "hover", "click" }
local CLICK_CLOSES = { stay = "Stay Open", auto = "Hide After Leaving" }
local CLICK_CLOSE_ORDER = { "stay", "auto" }
local ANIMATIONS = {
    instant = "Instant", fade = "Fade", slide = "Slide", fadeslide = "Fade and Slide", grow = "Grow", cascade = "Cascade",
}
local ANIMATION_ORDER = { "instant", "fade", "slide", "fadeslide", "grow", "cascade" }
local SLIDE_DISTANCE = 12   -- how far a sliding flyout travels, in UI units
local GROW_FROM = 0.6       -- the scale a growing flyout starts at
local BACK = 1.70158        -- overshoot of the Back easing
local EASINGS = {
    linear = function(t) return t end,
    out = function(t) return 1 - (1 - t) ^ 3 end,
    ["in"] = function(t) return t ^ 3 end,
    inout = function(t) return t < 0.5 and 4 * t ^ 3 or 1 - (-2 * t + 2) ^ 3 / 2 end,
    back = function(t) return 1 + (BACK + 1) * (t - 1) ^ 3 + BACK * (t - 1) ^ 2 end,
}
local EASING_NAMES = { linear = "Linear", out = "Ease Out", ["in"] = "Ease In", inout = "Ease In Out", back = "Overshoot" }
local EASING_ORDER = { "linear", "out", "in", "inout", "back" }
local ICON_PATH = "Interface\\Icons\\"
local MAIN_ICONS = {
    brew = "Poisons Skill", poisons = "Envenomed Blade", dualwield = "Dual Wield", stone = "Sharpening Stone",
    last = "Last Applied", custom = "Custom",
}
local MAIN_ICON_ORDER = { "brew", "poisons", "dualwield", "stone", "---", "last", "custom" }
local MAIN_ICON_FILES = {
    brew = ICON_PATH .. "Trade_BrewPoison", poisons = ICON_PATH .. "Ability_Poisons",
    dualwield = ICON_PATH .. "Ability_DualWield", stone = ICON_PATH .. "INV_Stone_SharpeningStone_01",
}

local db, main, fly, skin
local TrackApplied   -- defined with the applied highlight below; opening the flyout calls it
local buttons, items = {}, {}
local spellItem = {}   -- use spell -> item, for every item seen in your bags
local itemSpell = {}   -- item -> use spell, the same pairs the other way
local shown = 0   -- flyout buttons placed by the last Layout; `items` can run ahead of it in combat
local pending = false

local function Get(key)
    local v = db and db[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

-- A masked shape's art keeps a transparent margin around its opening.
-- The icon, mask and border are drawn larger than the button until the opening fills it, as EllesmereUI's own icons do.
-- `shape` defaults to the dock's Icon Shape; the restock buttons pass their own.
local function ApplyShape(b, shape)
    shape = shape or Get("shape")
    local mask = EUI.SHAPE_MASKS[shape]
    local icon, w = b.icon, b:GetWidth()
    icon:ClearAllPoints()
    if mask then
        local visible = (128 - 2 * (EUI.SHAPE_INSETS[shape] or 17)) / 128
        icon:SetPoint("CENTER")
        icon:SetSize(w / visible, w / visible)
        if not b.mask then
            b.mask = b:CreateMaskTexture()
            b.mask:SetAllPoints(icon)
        end
        b.mask:SetTexture(mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        if not b.masked then
            icon:AddMaskTexture(b.mask)
            b.hl:AddMaskTexture(b.mask)
            b.masked = true
        end
        local half = (0.5 - ZOOM) / visible
        icon:SetTexCoord(0.5 - half, 0.5 + half, 0.5 - half, 0.5 + half)
        b.shapeBorder:SetTexture(EUI.SHAPE_BORDERS[shape])
        b.shapeBorder:Show()
        b.edge:SetBackdropBorderColor(0, 0, 0, 0)
    else
        if b.masked then
            icon:RemoveMaskTexture(b.mask)
            b.hl:RemoveMaskTexture(b.mask)
            b.masked = false
        end
        icon:SetAllPoints()
        local z = shape == "cropped" and ZOOM or 0
        icon:SetTexCoord(z, 1 - z, z, 1 - z)
        b.shapeBorder:Hide()
        b.edge:SetBackdropBorderColor(0, 0, 0, shape == "cropped" and 1 or 0)
    end
end

-- Icon, masked highlight, shape border, and a 1px edge frame that also carries the count text.
local function Decorate(b, texture)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    if texture then b.icon:SetTexture(texture) end
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(b.icon)
    b.hl:SetColorTexture(1, 1, 1, 0.15)
    b.shapeBorder = b:CreateTexture(nil, "OVERLAY")
    b.shapeBorder:SetAllPoints(b.icon)
    b.shapeBorder:SetVertexColor(0, 0, 0)
    b.edge = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.edge:SetAllPoints()
    b.edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    -- Unsnapped, so animated icons glide instead of stepping whole pixels.
    for _, tex in ipairs({ b.icon, b.hl, b.shapeBorder }) do
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
    end
end

-- The saved order, minus unknown names, with any type it lacks appended in default order.
local orderedCache   -- cleared whenever db.order changes (InvalidateOrder)
local function InvalidateOrder() orderedCache = nil end

local function Ordered()
    if orderedCache then return orderedCache end
    local out, seen = {}, {}
    for _, name in ipairs(db and db.order or {}) do
        local g = GROUP_BY_NAME[name]
        if g and not seen[name] then out[#out + 1], seen[name] = g, true end
    end
    for _, g in ipairs(GROUPS) do
        if not seen[g.name] then out[#out + 1] = g end
    end
    if db then orderedCache = out end   -- the saved order is only known once settings load
    return out
end

local function IsHidden(g)
    return db and db.hidden and db.hidden[g.name] or false
end

local ownedGroup = {}   -- type name -> true while any of its ranks is in the bags (set by Collect)
local requested = {}    -- items whose data was asked for once already

-- The count text on every shown flyout button: amount, the user's eUI font, size, outline, color and place.
-- textOnly rewrites just the amounts (a bag change).
-- FontStrings are not protected, so this also runs in combat.
local function StyleCounts(textOnly)
    local showCount = Get("showCount")
    local font = skin and skin.GetFont() or STANDARD_TEXT_FONT
    local point, color, outline = Get("countPoint"), Get("countColor"), Get("countOutline")
    local flags = (outline == "OUTLINE" or outline == "THICKOUTLINE") and outline or ""
    local shadow = outline == "SHADOW" and 1 or 0
    local x = (point:find("LEFT") and COUNT_INSET or point:find("RIGHT") and -COUNT_INSET or 0) + Get("countX")
    local y = (point:find("TOP") and -COUNT_INSET or point:find("BOTTOM") and COUNT_INSET or 0) + Get("countY")
    for i = 1, shown do
        local b = buttons[i]
        b.count:SetText(showCount and C_Item.GetItemCount(b.itemID) or "")
        if showCount and not textOnly then
            b.count:SetFont(font, Get("countSize"), flags)
            b.count:SetShadowColor(0, 0, 0, 1)
            b.count:SetShadowOffset(shadow, -shadow)
            b.count:SetTextColor(color.r, color.g, color.b)
            b.count:ClearAllPoints()
            b.count:SetPoint(point, b, point, x, y)
        end
    end
end

local function Collect()
    wipe(items)
    wipe(ownedGroup)
    local highest = Get("highestOnly")
    for _, group in ipairs(Ordered()) do
        local listed, hidden = false, IsHidden(group)
        for i = #group, 1, -1 do
            local id = group[i]
            if C_Item.GetItemCount(id) > 0 then
                ownedGroup[group.name] = true
                local _, spellID = C_Item.GetItemSpell(id)
                if spellID then
                    spellItem[spellID], itemSpell[id] = id, spellID
                elseif not requested[id] then
                    requested[id] = true
                    C_Item.RequestLoadItemDataByID(id)
                end
                if not hidden and not (highest and listed) then
                    items[#items + 1] = id
                    listed = true
                end
            end
        end
    end
end

-- The flyout's anchor, pulled back toward the button by `back` units (the slide animation).
-- Per flyout direction: the edge facing the button, the button's edge it attaches to, and the unit step outward.
local DIR = {
    UP = { near = "BOTTOM", far = "TOP", x = 0, y = 1 },
    DOWN = { near = "TOP", far = "BOTTOM", x = 0, y = -1 },
    LEFT = { near = "RIGHT", far = "LEFT", x = -1, y = 0 },
    RIGHT = { near = "LEFT", far = "RIGHT", x = 1, y = 0 },
}

local curDir = "LEFT"   -- the direction in use: the setting, flipped when the screen edge is too close (Layout)

-- The setting, or its opposite when the flyout (`length` long) would not fit between the button and the screen edge.
local OPPOSITE = { UP = "DOWN", DOWN = "UP", LEFT = "RIGHT", RIGHT = "LEFT" }
local function FittingDirection(length)
    local dir = Get("direction")
    local l, r, b, t = main:GetLeft(), main:GetRight(), main:GetBottom(), main:GetTop()
    if not l then return dir end
    local need = length + Get("spacing")
    local room = { LEFT = l, RIGHT = UIParent:GetWidth() - r, DOWN = b, UP = UIParent:GetHeight() - t }
    if room[dir] < need and room[OPPOSITE[dir]] >= need then return OPPOSITE[dir] end
    return dir
end

local function PlaceFlyout(back)
    local d, dist = DIR[curDir], Get("spacing") - back
    fly:ClearAllPoints()
    fly:SetPoint(d.near, main, d.far, d.x * dist, d.y * dist)
end

-- Open/close state, animated by the main button's OnUpdate.
-- The flyout holds secure buttons, so it is only shown, hidden or moved out of combat; a fight freezes it as it is until combat ends.
local progress, target = 0, 0
local readApplied = true      -- read weapon enchants on the next frame (an enchant event, opening, a setting)
local overTime, outTime = 0, 0
local closeAfterCombat = false   -- Close After Use fired in combat; the flyout closes when it ends
local dockClickedAt = -math.huge -- when a flyout item was last clicked (Close After Use answers only those casts)
local dockClickedSpell           -- that item's use spell; the next start of it is the dock's cast
local dockCastGUID               -- the dock's cast in progress; only its success closes, only its failure disarms
local CLICK_WINDOW = 2           -- seconds from a flyout click to its cast starting (latency, a replace-enchant prompt)
local holdClosed = false   -- Close After Use closed it; hover does not reopen until the mouse leaves
local emptiedAt = -math.huge -- when the bags last ran out of everything the dock lists

-- A flyout icon at its slot, pulled back toward the main button by `back` units.
local function PlaceButton(b, back)
    local d, off = DIR[curDir], b.off - back
    b:ClearAllPoints()
    b:SetPoint(d.near, fly, d.near, d.x * off, d.y * off)
end

-- Cascade: each icon fades in and slides one slot outward, `stagger` seconds after the one before.
local function ItemDuration() return math.max(Get("duration"), 0.01) end

local function TotalDuration()
    local d = ItemDuration()
    if Get("animation") ~= "cascade" then return d end
    return d + math.max(shown - 1, 0) * Get("stagger")
end

local function ApplyCascade(e)
    local d, stagger, now = ItemDuration(), Get("stagger"), progress * TotalDuration()
    local step = Get("itemSize") + Get("spacing")
    for i = 1, shown do
        local b = buttons[i]
        local t = e(Saturate((now - (i - 1) * stagger) / d))
        b:SetAlpha(Saturate(t))
        PlaceButton(b, (1 - t) * step)
    end
end

local function ApplyProgress()
    local anim = Get("animation")
    local e = EASINGS[Get("easing")] or EASINGS.out
    if anim == "cascade" then
        fly:SetAlpha(1)
        fly.bg:SetAlpha(Saturate(e(progress)))
        PlaceFlyout(0)
        fly:SetScale(1)
        ApplyCascade(e)
        return
    end
    fly.bg:SetAlpha(1)
    local t = e(progress)
    local fade = anim == "fade" or anim == "fadeslide"
    fly:SetAlpha(fade and Saturate(t) or 1)
    PlaceFlyout((anim == "slide" or anim == "fadeslide") and (1 - t) * SLIDE_DISTANCE or 0)
    fly:SetScale(anim == "grow" and math.max(0.01, GROW_FROM + (1 - GROW_FROM) * t) or 1)
end

-- Puts the flyout at the end of its open or close: fully shown, or hidden.
local function FinishAnimation()
    progress = target
    ApplyProgress()
    if target == 0 then fly:Hide() end
end

-- ponytail: the flyout opens and closes only out of combat, since it holds secure buttons.
-- Secure handlers (SecureHandlerWrapScript showing it from OnEnter/OnClick) would allow opening it mid-fight.
local function SetOpen(open)
    if InCombatLockdown() or (open and shown == 0) then return end
    target = open and 1 or 0
    if open then
        fly:Show()
        TrackApplied()
    end
    if Get("animation") == "instant" then FinishAnimation() end
end

-- Poison effects. Particles are tiny frames animated by AnimationGroups (no per-frame Lua).
-- The bubble art is EllesmereUI's circle shape, tinted.
local BUBBLES, DROPLETS, SPARKLES = 6, 10, 5
local SPLASH_TIME = 0.5   -- seconds the splash plays
local TIMER_SLACK = 0.05  -- keeps a timer from landing on the edge of the window it ends
local SPARKLE_ART = "Interface\\Cooldown\\star4"
local fx = { bubbles = {}, droplets = {}, sparkles = {} }

local function Particle(parent, size, art)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f:SetAlpha(0)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetTexture(art or EUI.SHAPE_MASKS.circle)
    t:SetBlendMode("ADD")
    f.tex = t
    local ag = f:CreateAnimationGroup()
    f.ag = ag
    f.move = ag:CreateAnimation("Translation")
    f.fadeIn = ag:CreateAnimation("Alpha")
    f.fadeIn:SetFromAlpha(0)
    f.fadeIn:SetToAlpha(1)
    f.fadeOut = ag:CreateAnimation("Alpha")
    f.fadeOut:SetFromAlpha(1)
    f.fadeOut:SetToAlpha(0)
    f.scale = ag:CreateAnimation("Scale")
    return f
end

-- One bubble rise from a random spot along the bottom edge of `anchor` (the dock button unless given).
-- Restock.lua raises them from its buttons too.
local function LaunchBubble(f, anchor)
    anchor = anchor or main
    local w = anchor:GetWidth()
    local life = 1.2 + math.random() * 1.2
    f:ClearAllPoints()
    f:SetPoint("CENTER", anchor, "BOTTOM", (math.random() - 0.5) * w * 0.8, w * 0.2)
    f.move:SetOffset((math.random() - 0.5) * 8, w * (0.6 + math.random() * 0.5))
    f.move:SetDuration(life)
    f.move:SetSmoothing("OUT")
    f.fadeIn:SetDuration(life * 0.25)
    f.fadeOut:SetStartDelay(life * 0.5)
    f.fadeOut:SetDuration(life * 0.5)
    f.scale:SetScaleFrom(0.4, 0.4)
    f.scale:SetScaleTo(1, 1)
    f.scale:SetDuration(life)
    f.ag:Play()
end

-- One sparkle: a star twinkling up and spinning at a random spot around the button.
local function LaunchSparkle(f)
    local w = main:GetWidth()
    local life = 0.6 + math.random() * 0.5
    local angle, dist = math.random() * 2 * math.pi, w * (0.2 + math.random() * 0.4)
    f:ClearAllPoints()
    f:SetPoint("CENTER", main, "CENTER", math.cos(angle) * dist, math.sin(angle) * dist)
    f.move:SetOffset(0, 3)
    f.move:SetDuration(life)
    f.fadeIn:SetDuration(life * 0.3)
    f.fadeOut:SetStartDelay(life * 0.5)
    f.fadeOut:SetDuration(life * 0.5)
    f.scale:SetScaleFrom(0.2, 0.2)
    f.scale:SetScaleTo(1, 1)
    f.scale:SetDuration(life * 0.5)
    f.spin:SetDegrees(math.random() < 0.5 and -90 or 90)
    f.spin:SetDuration(life)
    f.ag:Play()
    f.spinAg:Stop()
    f.spinAg:Play()
end

local hovering = false    -- mouse over the dock, or the flyout open (Tick keeps it current)
local anyPoison = false   -- a poison on either weapon (Tick keeps it current)
local anyStone = false    -- a stone or oil on either weapon (Tick keeps it current)

local function DockShown() return main and main:IsShown() end

-- An effect runs while the dock shows, effects are on, its color is visible, and the hover and applied conditions allow it.
local function EffectOn(colorKey, applied)
    local needHover = Get("bubblesOnHover") or Get("mouseover")
    return DockShown() and Get("fx") and (Get(colorKey).a or 1) > 0 and (hovering or not needHover)
        and (applied or not Get("bubblesOnApplied"))
end

local function BubblesOn() return EffectOn("bubbleColor", anyPoison) end

local function SparklesOn() return EffectOn("sparkleColor", anyStone) end

-- Launches a particle after `delay` if its effect is still on; a particle already waiting is left alone.
-- f.launch and f.isOn are set when the particle is made; f.relaunch is its one timer callback.
local function Schedule(f, delay)
    if f.scheduled then return end
    f.scheduled = true
    if not f.relaunch then
        f.relaunch = function()
            f.scheduled = false
            if f.isOn() and not f.ag:IsPlaying() then f.launch(f) end
        end
    end
    C_Timer.After(delay, f.relaunch)
end

-- Starts each idle particle of a pool after a random pause while its effect is on.
-- Turning effects off or the color invisible stops them at once; the hover and applied conditions let running ones finish.
local function SyncPool(pool, colorKey, isOn)
    local c, on = Get(colorKey), isOn()
    for _, f in ipairs(pool) do
        f.tex:SetVertexColor(c.r, c.g, c.b)
        f.tex:SetAlpha(c.a or 1)
        if on and not f.ag:IsPlaying() then
            Schedule(f, math.random() * (Get("bubblesOnHover") and 0.5 or 2))
        elseif not Get("fx") or (c.a or 1) <= 0 then
            f.ag:Stop()
            if f.spinAg then f.spinAg:Stop() end
        end
    end
end

local function SyncBubbles()
    SyncPool(fx.bubbles, "bubbleColor", BubblesOn)
    SyncPool(fx.sparkles, "sparkleColor", SparklesOn)
end

-- A ring of droplets from `pool` (DROPLETS particles) bursting out of `anchor`, in color `c` at `alpha`.
-- `size` (default 1) scales its reach and droplets. Restock.lua bursts its buttons with its own pool.
local function Burst(pool, anchor, c, alpha, size)
    size = size or 1
    local reach = anchor:GetWidth() * 0.9 * size
    for i = 1, DROPLETS do
        local f = pool[i]
        local angle = (i / DROPLETS + math.random() * 0.05) * 2 * math.pi
        local dist = reach * (0.7 + math.random() * 0.5)
        f:ClearAllPoints()
        f:SetPoint("CENTER", anchor, "CENTER")
        f.ag:Stop()
        f.tex:SetVertexColor(c.r, c.g, c.b)
        f.tex:SetAlpha(alpha)
        f.move:SetOffset(math.cos(angle) * dist, math.sin(angle) * dist)
        f.move:SetDuration(0.45)
        f.move:SetSmoothing("OUT")
        f.fadeIn:SetDuration(0.05)
        f.fadeOut:SetStartDelay(0.15)
        f.fadeOut:SetDuration(0.3)
        f.scale:SetScaleFrom(size, size)
        f.scale:SetScaleTo(0.3 * size, 0.3 * size)
        f.scale:SetDuration(0.45)
        f.ag:Play()
    end
end

-- A ring of droplets bursting out of the button.
local function Splash(kind)
    if not Get("fx") or Get("splashAlpha") <= 0 then return end
    Burst(fx.droplets, main, Get(kind == "stone" and "sparkleColor" or "bubbleColor"), Get("splashAlpha"))
end

local function CreateFx()
    fx.layer = CreateFrame("Frame", nil, main)
    fx.layer:SetAllPoints()
    fx.layer:SetFrameLevel(main:GetFrameLevel() + 5)
    for i = 1, BUBBLES do
        local f = Particle(fx.layer, 3 + math.random() * 3)
        f.launch, f.isOn = LaunchBubble, BubblesOn
        f.ag:SetScript("OnFinished", function()
            if BubblesOn() then Schedule(f, math.random() * 1.5) end
        end)
        fx.bubbles[i] = f
    end
    for i = 1, DROPLETS do fx.droplets[i] = Particle(fx.layer, 3 + math.random() * 2) end
    for i = 1, SPARKLES do
        local f = Particle(fx.layer, 8 + math.random() * 5, SPARKLE_ART)
        f.spinAg = f.tex:CreateAnimationGroup()
        f.spin = f.spinAg:CreateAnimation("Rotation")
        f.launch, f.isOn = LaunchSparkle, SparklesOn
        f.ag:SetScript("OnFinished", function()
            if SparklesOn() then Schedule(f, 0.2 + math.random() * 1.2) end
        end)
        fx.sparkles[i] = f
    end
    SyncBubbles()
end

-- Applied enchants: while the flyout is open, the icons of the types on a weapon carry a glow in the icon's shape.
-- The enchant's icon names its type.
local GLOW_OUTSET = 1.12      -- glow art size relative to the icon art
local GLOW_STYLES = { static = "Static", pulse = "Pulse" }
local GLOW_STYLE_ORDER = { "static", "pulse" }
local GLOW_LOW = 0.35                             -- share of the glow's opacity at the bottom of a pulse

-- The secret-value guard: restricted enchant info reads as nothing applied.
local function Readable(v) return not (issecretvalue and issecretvalue(v)) end

-- Built on first use and cleared when one of our items' data arrives.
-- A build that missed some icons is retried on a later miss, at most every ICON_RETRY seconds, so a late icon still gets its kind.
local ICON_RETRY = 30
local iconKind, iconKindPartial, iconKindAt   -- iconKind: item icon -> the types (groups) that use it
local function GroupsOfIcon(icon)
    if not iconKind or (iconKindPartial and iconKind[icon] == nil and GetTime() - iconKindAt >= ICON_RETRY) then
        iconKind, iconKindPartial, iconKindAt = {}, false, GetTime()
        for _, g in ipairs(GROUPS) do
            for i = 1, #g do
                local tex = C_Item.GetItemIconByID(g[i])
                if not tex then
                    iconKindPartial = true
                else
                    local list = iconKind[tex]
                    if not list then
                        list = {}
                        iconKind[tex] = list
                    end
                    if list[#list] ~= g then list[#list + 1] = g end
                end
            end
        end
    end
    return iconKind[icon]
end

-- The kinds an icon stands for, as text, for the debug command.
local function KindsOfIcon(icon)
    local kinds = {}
    for _, g in ipairs(GroupsOfIcon(icon) or {}) do kinds[#kinds + 1] = g.kind end
    return #kinds > 0 and table.concat(kinds, "/") or "nil"
end

local SLOTS = { "MainHand", "OffHand" }

-- C_Item.GetWeaponEnchantInfo is WoW Forever's API (wow-ui-source, forever branch, ItemDocumentation.lua):
-- it returns a list of { hasEnchant, enchantType, timeLeft, charges, enchantID, enchantIconID } per weapon slot.
-- Calls fn(slot, entry) for each enchant entry on both hands, or fn(slot, nil, why) when a hand cannot be read.
-- Returns false when the client has no weapon enchant info at all.
local function EachEnchant(fn)
    if not (C_Item.GetWeaponEnchantInfo and Enum.WeaponSlot) then return false end
    for _, slot in ipairs(SLOTS) do
        local list = C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot[slot])
        if not Readable(list) then
            fn(slot, nil, "restricted")
        elseif type(list) == "table" then
            for _, e in ipairs(list) do fn(slot, e) end
        end
    end
    return true
end

local expiryTimer, expiryAt
local EXPIRY_SLACK = 0.2   -- seconds past the soonest expiry for the follow-up read

local appliedGroups = {}   -- type name -> true while something of that type is on a weapon
local appliedMain = {}     -- the same for the main hand alone (Effects Only When Applied: Main Hand Only)

-- Reads which types are on both hands into appliedGroups, which the highlight and Effects Only When Applied use.
-- It also schedules a read for when the soonest of them runs out.
local function ReadApplied()
    wipe(appliedGroups)
    wipe(appliedMain)
    local soonest
    EachEnchant(function(slot, e)
        if e and Readable(e.hasEnchant) and Readable(e.enchantIconID) and Readable(e.timeLeft)
            and e.hasEnchant and e.enchantIconID and type(e.timeLeft) == "number" and e.timeLeft > 0 then
            for _, g in ipairs(GroupsOfIcon(e.enchantIconID) or {}) do
                appliedGroups[g.name] = true
                if slot == "MainHand" then appliedMain[g.name] = true end
            end
            soonest = math.min(soonest or e.timeLeft, e.timeLeft)
        end
    end)
    local at = soonest and GetTime() + soonest / 1000 + EXPIRY_SLACK
    if expiryTimer and at and expiryAt and math.abs(at - expiryAt) < EXPIRY_SLACK then return end
    if expiryTimer then expiryTimer:Cancel() end
    expiryAt = at
    expiryTimer = at and C_Timer.NewTimer(at - GetTime(), function()
        expiryTimer = nil
        readApplied = true
    end) or nil
end

-- Its own glow rather than EllesmereUI.Glows, which is not part of EllesmereUI's plugin API.
local function UpdateApplied()
    local shape = Get("shape")
    local artKey = EUI.SHAPE_BORDERS[shape] and shape or "square"
    local art = EUI.SHAPE_BORDERS[artKey]
    local visible = (128 - 2 * (EUI.SHAPE_INSETS[artKey] or 17)) / 128
    for i = 1, shown do
        local b = buttons[i]
        -- ponytail: by type, so every listed rank of the applied type glows, and types sharing an icon glow together.
        -- The enchant ID per item would tell ranks and look-alike types apart.
        local group = GROUP_OF_ITEM[b.itemID]
        local on = Get("applied") and group and appliedGroups[group.name] or false
        if on then
            local w = b:GetWidth() / visible * GLOW_OUTSET
            local c, style = Get("glowColor"), Get("glowStyle")
            local period = style ~= "static" and Get("glowSpeed") or nil
            b.glow:SetTexture(art)
            b.glow:SetSize(w, w)
            b.glow:SetVertexColor(c.r, c.g, c.b)
            b.glow:SetAlpha(c.a or 1)
            b.glow:Show()
            if period then
                -- Our own key, not the animation getters: those return rounded floats and would restart it every read.
                local key = period .. ":" .. (c.a or 1)
                if b.glowKey ~= key then
                    b.glowKey = key
                    b.glowAnim:Stop()
                    b.glowPulse:SetFromAlpha(c.a or 1)
                    b.glowPulse:SetToAlpha((c.a or 1) * GLOW_LOW)
                    b.glowPulse:SetDuration(period)
                end
                if not b.glowAnim:IsPlaying() then b.glowAnim:Play() end
            else
                b.glowAnim:Stop()
            end
        else
            b.glowAnim:Stop()
            b.glow:Hide()
        end
    end
end

-- Over the button or the flyout; while it is open, anywhere in the box spanning both counts.
-- Crossing the spacing, even beside a narrower button, then never starts the hide delay.
local BRIDGE_SLACK = 2   -- extra units past the spacing, for the edge pixels
local function OverDock()
    if not fly:IsShown() then return main:IsMouseOver() end
    if main:IsMouseOver() or fly:IsMouseOver() then return true end
    local ms, fs = main:GetEffectiveScale(), fly:GetEffectiveScale()
    local ml, mr, mb, mt = main:GetLeft(), main:GetRight(), main:GetBottom(), main:GetTop()
    local fl, fr, fb, ft = fly:GetLeft(), fly:GetRight(), fly:GetBottom(), fly:GetTop()
    if not (ml and fl) then return false end
    local slack = BRIDGE_SLACK * ms
    local x, y = GetCursorPosition()
    return x >= math.min(ml * ms, fl * fs) - slack and x <= math.max(mr * ms, fr * fs) + slack
        and y >= math.min(mb * ms, fb * fs) - slack and y <= math.max(mt * ms, ft * fs) + slack
end

local ALPHA_EPSILON = 0.002   -- GetAlpha returns a rounded value
local MOUSEOVER_FADE = 0.2   -- seconds for the mouseover-only button to fade in or out

-- Returns false when nothing reads the result right now.
TrackApplied = function()
    if not (fly:IsShown() or (Get("fx") and Get("bubblesOnApplied"))) then return false end
    ReadApplied()
    if fly:IsShown() then UpdateApplied() end
    local poison, stone = false, false
    for name in pairs(Get("appliedHand") == "main" and appliedMain or appliedGroups) do
        if GROUP_BY_NAME[name].kind == "poison" then poison = true else stone = true end
    end
    if poison ~= anyPoison or stone ~= anyStone then
        anyPoison, anyStone = poison, stone
        SyncBubbles()
    end
    return true
end

-- ponytail: polls every frame (a few table lookups and two IsMouseOver calls).
-- Drive it from OnEnter/OnLeave and only run while animating if this ever shows up in a profile.
local function Tick(_, elapsed)
    if readApplied then
        readApplied = false
        TrackApplied()
    end
    local over = OverDock()
    -- Alpha is not protected, so the mouseover fade keeps working in combat.
    local want = (not Get("mouseover") or over or progress > 0 or EUI:IsUnlockModeActive()) and Get("opacity") or 0
    local alpha = main:GetAlpha()
    if math.abs(alpha - want) > ALPHA_EPSILON then
        local step = elapsed / MOUSEOVER_FADE
        main:SetAlpha(want > alpha and math.min(want, alpha + step) or math.max(want, alpha - step))
    end
    local nowHovering = over or progress > 0
    if nowHovering ~= hovering then
        hovering = nowHovering
        if Get("bubblesOnHover") or Get("mouseover") then SyncBubbles() end
    end
    if InCombatLockdown() then return end
    if over then
        overTime, outTime = overTime + elapsed, 0
    else
        overTime, outTime, holdClosed = 0, outTime + elapsed, false
    end
    local hover = Get("openMode") == "hover"
    if target == 0 and hover and not holdClosed and (main:IsMouseOver() or (progress > 0 and over))
        and overTime >= Get("openDelay")
        and not EUI:IsUnlockModeActive() then
        SetOpen(true)
    elseif target == 1 and outTime >= Get("closeDelay") and (hover or Get("clickClose") == "auto") then
        SetOpen(false)
    end
    if progress ~= target then
        local step = elapsed / TotalDuration()
        progress = target > progress and math.min(target, progress + step) or math.max(target, progress - step)
        if progress == target then FinishAnimation() else ApplyProgress() end
    end
end

-- Custom accepts a file ID, an icon name ("Ability_Rogue_Sprint") or a full texture path.
local function MainIconTexture()
    local mode = Get("mainIcon")
    if mode == "last" and db and db.lastIcon then
        return db.lastIcon
    elseif mode == "custom" then
        local v = strtrim(Get("customIcon") or "")
        if v ~= "" then return tonumber(v) or (v:find("[\\/]") and v or ICON_PATH .. v) end
    end
    return MAIN_ICON_FILES[mode] or MAIN_ICON_FILES.brew
end

local function MakeButton(i)
    local b = CreateFrame("Button", nil, fly, "SecureActionButtonTemplate")
    -- Add-on clicks count as key presses: they act on down or up per ActionButtonUseKeyDown, so take both.
    b:RegisterForClicks("AnyUp", "AnyDown")
    -- The secure item action aims at target-slotN only when the item asks for a weapon to coat.
    b:SetAttribute("*type1", "item")
    b:SetAttribute("*type2", "item")
    b:SetAttribute("*target-slot1", 16)
    b:SetAttribute("*target-slot2", 17)
    Decorate(b)
    b.glow = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.glow:SetPoint("CENTER")
    b.glow:SetBlendMode("ADD")
    b.glow:Hide()
    b.glowAnim = b.glow:CreateAnimationGroup()
    b.glowAnim:SetLooping("BOUNCE")
    b.glowPulse = b.glowAnim:CreateAnimation("Alpha")
    b.glowPulse:SetSmoothing("IN_OUT")
    b.count = b.edge:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b:SetScript("OnEnter", function(self)
        local mode = Get("tooltip")
        if mode == "off" then return end
        GameTooltip:SetOwner(self, (curDir == "LEFT" or curDir == "RIGHT") and "ANCHOR_TOP" or "ANCHOR_RIGHT")
        if mode == "name" then
            local name, _, quality = C_Item.GetItemInfo(self.itemID)
            local r, g, bl = C_Item.GetItemQualityColor(quality or 1)
            if name then GameTooltip:SetText(name, r, g, bl) else GameTooltip:SetItemByID(self.itemID) end
        else
            GameTooltip:SetItemByID(self.itemID)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("PostClick", function(_, button)
        if button == "LeftButton" or button == "RightButton" then
            dockClickedAt, dockClickedSpell = GetTime(), itemSpell[b.itemID]
        end
    end)
    buttons[i] = b
    return b
end

-- An item's use spell finished: splash in its kind's color, and it becomes Last Applied.
-- Close After Use: shut the flyout and keep hover from reopening it until the mouse leaves.
local function CloseAfterUse()
    if target ~= 1 then return end
    SetOpen(false)
    holdClosed = true
end

local function OnApplied(itemID, castGUID)
    local icon = C_Item.GetItemIconByID(itemID)
    if icon then db.lastIcon = icon end
    if Get("mainIcon") == "last" and icon then main.icon:SetTexture(icon) end
    Splash(GROUP_OF_ITEM[itemID] and GROUP_OF_ITEM[itemID].kind)
    if Get("closeOnUse") and target == 1 and castGUID and castGUID == dockCastGUID then
        dockCastGUID = nil
        if InCombatLockdown() then closeAfterCombat = true else CloseAfterUse() end
    end
end

-- Whether the dock shows with `n` items listed.
-- With Hide When None in Bags, it stays up for one splash after the last stack is used.
local function DockVisible(n)
    local landing = n == 0 and GetTime() - emptiedAt < SPLASH_TIME
    local carried = next(ownedGroup) ~= nil   -- every listed item is carried, so this covers n > 0 too
    return Get("enabled") and (EUI:IsUnlockModeActive() or carried or not Get("hideEmpty") or landing)
end

-- The main button's look, and while it may change (out of combat, or nothing protected yet) its size and visibility.
local notifiedSize   -- the button size Unlock Mode was last told about

local function ApplyMain(n)
    main.icon:SetTexture(MainIconTexture())
    if InCombatLockdown() and main:IsProtected() then
        ApplyShape(main)
        return
    end
    main:SetSize(Get("size"), Get("size"))
    if notifiedSize ~= Get("size") and EUI.NotifyElementResized and not InCombatLockdown() then
        notifiedSize = Get("size")
        EUI.NotifyElementResized(ADDON)
    end
    ApplyShape(main)
    local wasShown = main:IsShown()
    main:SetShown(DockVisible(n))
    if not main:IsShown() then hovering = false end
    if main:IsShown() == wasShown then return end
    SyncBubbles()
    if main:IsShown() then readApplied = true end
end

local inLayout = false   -- Layout is running; a position re-apply it triggers does not start another

-- Secure buttons can only be changed out of combat; a change in combat waits for it to end.
local function LayoutBody()
    if not main then return end
    if InCombatLockdown() then
        pending = true
        ApplyMain(#items)
        return
    end
    pending = false
    local n, shownBefore = #items, shown
    ApplyMain(n)
    -- An empty or hidden dock drops any open or closing flyout, so nothing resumes half-faded later.
    if (n == 0 or not main:IsShown()) and (target ~= 0 or progress ~= 0) then
        target, progress = 0, 0
        fly:Hide()
    end
    local size, gap = Get("itemSize"), Get("spacing")
    local long = math.max(n, 1) * (size + gap) - gap
    curDir = FittingDirection(long)
    PlaceFlyout(0)
    if curDir == "UP" or curDir == "DOWN" then fly:SetSize(size, long) else fly:SetSize(long, size) end
    for i = 1, n do
        local b = buttons[i] or MakeButton(i)
        local id = items[i]
        b.itemID = id
        b:SetSize(size, size)
        ApplyShape(b)
        b.off = (i - 1) * (size + gap)
        b:SetAlpha(1)
        PlaceButton(b, 0)
        b.icon:SetTexture(C_Item.GetItemIconByID(id))
        -- ponytail: in combat a used-up stack keeps its button until combat ends, since secure buttons are locked then.
        -- The next rank waits until then.
        b:SetAttribute("item", "item:" .. id)
        b:Show()
    end
    for i = n + 1, #buttons do buttons[i]:Hide() end
    shown = n
    StyleCounts()
    if progress ~= target and n ~= shownBefore then FinishAnimation() end
    fly.bg:SetShown(Get("background"))
    if fly:IsShown() then UpdateApplied() end
end

local function Layout()
    inLayout = true
    LayoutBody()
    inLayout = false
end

local previous = {}

-- Recollects the list; a full Layout only when it changed (or one is owed, or forced), else just the counts.
local function Refresh(force)
    wipe(previous)
    for i, id in ipairs(items) do previous[i] = id end
    Collect()
    -- Settings and editor changes pass force, so only a bag change counts as running out.
    if not force and #previous > 0 and #items == 0 then
        emptiedAt = GetTime()
        if Get("hideEmpty") then C_Timer.After(SPLASH_TIME + TIMER_SLACK, Layout) end
    end
    local same = #previous == #items
    for i = 1, #items do
        if previous[i] ~= items[i] then same = false end
    end
    if InCombatLockdown() then
        if force or not same then Layout() end
        StyleCounts(true)
    elseif force or not same or pending then
        Layout()
    else
        StyleCounts(true)
    end
end

local positionPending = false

local function SavedPoint()
    if InCombatLockdown() and main:IsProtected() then
        positionPending = true
        return
    end
    positionPending = false
    local p = Get("position")
    main:ClearAllPoints()
    if type(p) == "table" and p.point then
        main:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        main:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    end
end

local function CreateDock()
    main = CreateFrame("Button", "EllesmerePoisonsButton", UIParent)
    main:SetFrameStrata("MEDIUM")
    main:SetClampedToScreen(true)
    Decorate(main)

    -- The flyout (and the icons it creates later, one level above it) stays under the main button.
    -- Icons sliding out of it then pass behind the button.
    main:SetFrameLevel(20)
    fly = CreateFrame("Frame", nil, main)
    fly:SetFrameLevel(10)
    fly:Hide()
    fly.bg = CreateFrame("Frame", nil, fly)
    fly.bg:SetAllPoints()
    fly.bg:SetFrameLevel(fly:GetFrameLevel())
    fly.bg.plain = fly.bg:CreateTexture(nil, "BACKGROUND")
    fly.bg.plain:SetAllPoints()
    fly.bg.plain:SetColorTexture(0.05, 0.05, 0.05, 0.85)
    if skin then
        skin.Panel(fly.bg)
        fly.bg.plain:Hide()
    end

    main:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    main:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            EUI.OpenPlugin(ADDON)
        elseif Get("openMode") == "click" and not EUI:IsUnlockModeActive() then
            SetOpen(target == 0)
        end
    end)
    main:SetScript("OnUpdate", Tick)   -- runs exactly while the dock shows
    CreateFx()
    SavedPoint()
    Refresh(true)   -- forced: an empty first list would otherwise leave the button unsized
end

local function SetButtonSize(v)
    local size = Clamp(math.floor(v + 0.5), SIZE_MIN, SIZE_MAX)
    if size == Get("size") then return end
    db.size = size
    Layout()
end

local function RegisterUnlock()
    EUI:RegisterUnlockElements({
        EUI.MakeUnlockElement({
            key = ADDON, label = "Dock", group = "Poisons", order = 900,
            isHidden = function() return not Get("enabled") end,
            getFrame = function() return Get("enabled") and main or nil end,
            getSize = function() return Get("size"), Get("size") end,
            setWidth = function(_, w) SetButtonSize(w) end,
            setHeight = function(_, h) SetButtonSize(h) end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                db.position = { point = point, relPoint = relPoint or point, x = x, y = y }
            end,
            loadPos = function()
                local p = Get("position")
                if type(p) == "table" and p.point then
                    return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
                end
            end,
            clearPos = function()
                db.position = nil
                SavedPoint()
                Layout()   -- the flyout direction depends on where the button is
            end,
            applyPos = function()
                SavedPoint()
                if not inLayout then Layout() end
            end,
        }),
    }, ADDON)
    EUI:RegisterUnlockModeListener(ADDON, function(active)
        if active and not InCombatLockdown() then
            SetOpen(false)
            FinishAnimation()
        end
        Layout()
    end)
    ns.ElementOptions(ADDON, "General", "General", "GENERAL")
end

-- Points a mover's "Element Options" entry at a page of one of this plugin's modules.
-- ponytail: it writes eUI's internal settings map (no public API yet).
-- Creating the table when absent is safe: eUI merges entries made before its own map loads.
function ns.ElementOptions(key, moduleKey, page, section)
    local map = EUI._ELEMENT_SETTINGS_MAP or {}
    EUI._ELEMENT_SETTINGS_MAP = map
    map[key] = { module = EUI.GetPluginModuleKey(ADDON, moduleKey), page = page, sectionName = section }
end

-- An icon row for a settings page: drag to reorder, click to hide or show. Restock.lua makes one for its buttons too.
-- spec: list() -> keys in order, icon(key), label(key), isHidden(key), toggle(key), move(key, slot), hint, empty,
-- and optionally shape() for an icon shape other than the dock's.
local EDIT_SIZE, EDIT_GAP = 32, 6
local EDITOR_HEIGHT = EDIT_SIZE + 36

local function NewEditor(spec)
    local ed = { icons = {} }

    local function Icon(key)
        local b = CreateFrame("Button", nil, ed.row)
        Decorate(b)
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnClick", function()
            spec.toggle(key)
            ed.Refresh()
        end)
        b:SetScript("OnDragStart", function(self) self:SetAlpha(0.5) end)
        -- The drop slot is the icon column under the cursor.
        b:SetScript("OnDragStop", function()
            local x = GetCursorPosition() / ed.row:GetEffectiveScale()
            local left = ed.row:GetLeft() + ed.row:GetWidth() / 2 - ed.width / 2
            spec.move(key, math.floor((x - left) / (EDIT_SIZE + EDIT_GAP)) + 1)
            ed.Refresh()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L(spec.label(key)), 1, 1, 1)
            if spec.isHidden(key) then GameTooltip:AddLine(L("Hidden"), 0.6, 0.6, 0.6) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        ed.icons[key] = b
        return b
    end

    function ed.Refresh()
        if not ed.frame then return end
        local list = spec.list()
        local width = #list * (EDIT_SIZE + EDIT_GAP) - EDIT_GAP
        for _, b in pairs(ed.icons) do b:Hide() end
        ed.hint:SetText(L(#list > 0 and spec.hint or spec.empty))
        for i, key in ipairs(list) do
            local b = ed.icons[key] or Icon(key)
            local hidden = spec.isHidden(key)
            b.icon:SetTexture(spec.icon(key))
            b:SetSize(EDIT_SIZE, EDIT_SIZE)
            ApplyShape(b, spec.shape and spec.shape())
            b:ClearAllPoints()
            b:SetPoint("LEFT", ed.row, "CENTER", -width / 2 + (i - 1) * (EDIT_SIZE + EDIT_GAP), 0)
            b.icon:SetDesaturated(hidden)
            b:SetAlpha(hidden and 0.35 or 1)
            b:Show()
        end
        ed.width = width
    end

    -- Places the row at `y` on a page being built and returns its height. Built once, then moved to each new page.
    function ed.Build(parent, y)
        if not ed.frame then
            ed.frame = CreateFrame("Frame", nil, parent)
            ed.frame:SetHeight(EDITOR_HEIGHT)
            ed.row = CreateFrame("Frame", nil, ed.frame)
            ed.row:SetPoint("TOPLEFT", 0, -4)
            ed.row:SetPoint("TOPRIGHT", 0, -4)
            ed.row:SetHeight(EDIT_SIZE)
            ed.hint = ed.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            ed.hint:SetPoint("TOP", ed.row, "BOTTOM", 0, -8)
        end
        ed.frame:SetParent(parent)
        ed.frame:ClearAllPoints()
        ed.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        ed.frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
        ed.frame:Show()
        ed.Refresh()
        return EDITOR_HEIGHT
    end

    return ed
end
ns.NewEditor, ns.EDITOR_HEIGHT = NewEditor, EDITOR_HEIGHT

-- The type editor: only the types in your bags, in dock order.
local function EditorList()
    local list = {}
    for _, g in ipairs(Ordered()) do
        if ownedGroup[g.name] then list[#list + 1] = g.name end
    end
    return list
end

-- `to` is a slot among the shown types; types not in your bags keep their places in the full order.
local function MoveGroup(name, to)
    if not ownedGroup[name] then return end
    local visibleNames = {}
    for _, g in ipairs(Ordered()) do
        if ownedGroup[g.name] and g.name ~= name then visibleNames[#visibleNames + 1] = g.name end
    end
    table.insert(visibleNames, Clamp(to, 1, #visibleNames + 1), name)
    local names, k = {}, 0
    for _, g in ipairs(Ordered()) do
        if ownedGroup[g.name] then
            k = k + 1
            names[#names + 1] = visibleNames[k]
        else
            names[#names + 1] = g.name
        end
    end
    db.order = names
    InvalidateOrder()
    Refresh(true)
end

local editor = NewEditor({
    list = EditorList,
    icon = function(name)
        local g = GROUP_BY_NAME[name]
        return C_Item.GetItemIconByID(g[#g])
    end,
    label = function(name) return name end,
    isHidden = function(name) return IsHidden(GROUP_BY_NAME[name]) end,
    toggle = function(name)
        db.hidden = db.hidden or {}
        db.hidden[name] = not db.hidden[name] or nil
        Refresh(true)
    end,
    move = MoveGroup,
    hint = "Drag to reorder, click to hide or show",
    empty = "No poisons, stones or oils in your bags",
})

local function RefreshEditor() editor.Refresh() end
local function BuildEditor(parent, y) return editor.Build(parent, y) end

local LAYOUT_KEYS = {
    enabled = true, hideEmpty = true, size = true, itemSize = true, spacing = true, direction = true, shape = true,
    background = true, mainIcon = true, customIcon = true, animation = true,
}
local COUNT_KEYS = {
    showCount = true, countSize = true, countPoint = true, countColor = true, countOutline = true, countX = true, countY = true,
}
local FX_KEYS = {
    fx = true, bubblesOnHover = true, bubblesOnApplied = true, appliedHand = true, bubbleColor = true, sparkleColor = true, mouseover = true,
}
local GLOW_KEYS = { applied = true, glowColor = true, glowStyle = true, glowSpeed = true }

local function Set(key, value)
    db[key] = value
    if key == "highestOnly" then Refresh(true) elseif LAYOUT_KEYS[key] then Layout() elseif COUNT_KEYS[key] then StyleCounts() end
    if key == "shape" then RefreshEditor() end
    if FX_KEYS[key] or key == "enabled" then
        readApplied = true
        SyncBubbles()
    end
    if GLOW_KEYS[key] and fly:IsShown() then UpdateApplied() end
end

local function BuildPage(_, parent, yOffset)
    local W = EUI.Widgets
    local y = yOffset
    local function Header(text)
        local _, h = W:SectionHeader(parent, text, y)
        y = y - h
    end
    local function Row(left, right)
        local _, h = W:DualRow(parent, y, left, right)
        y = y - h
    end
    local function Toggle(text, key, tip, disabled, why)
        return { type = "toggle", text = text, tooltip = tip, disabled = disabled, disabledTooltip = why,
            getValue = function() return Get(key) end, setValue = function(v) Set(key, v); EUI:RefreshPage() end }
    end
    local function Slider(text, key, min, max, step, tip, disabled, why)
        return { type = "slider", text = text, min = min, max = max, step = step or 1, tooltip = tip,
            disabled = disabled, disabledTooltip = why,
            getValue = function() return Get(key) end, setValue = function(v) Set(key, v) end }
    end
    local function Dropdown(text, key, values, order, tip, disabled, why)
        return { type = "dropdown", text = text, values = values, order = order, tooltip = tip,
            disabled = disabled, disabledTooltip = why,
            getValue = function() return Get(key) end, setValue = function(v) Set(key, v); EUI:RefreshPage() end }
    end
    -- A color swatch; with alpha it stores { r, g, b, a }.
    local function Color(text, key, hasAlpha, tip, disabled, why)
        return { type = "colorpicker", text = text, hasAlpha = hasAlpha, tooltip = tip,
            disabled = disabled, disabledTooltip = why,
            getValue = function()
                local c = Get(key)
                return c.r, c.g, c.b, c.a or 1
            end,
            setValue = function(r, g, b, a)
                Set(key, { r = r, g = g, b = b, a = hasAlpha and (a or 1) or nil })
            end }
    end

    Header("POISONS, STONES AND OILS")
    if EUI.IsSearchPrebuild and EUI.IsSearchPrebuild() then
        y = y - EDITOR_HEIGHT
    else
        y = y - BuildEditor(parent, y)
    end

    Header("GENERAL")
    Row(Toggle("Enable", "enabled", "Shows the dock. Move it in EllesmereUI's Unlock Mode."),
        Toggle("Hide When None in Bags", "hideEmpty", "Hides the button while you carry no poisons, stones or oils."))
    Row(Toggle("Highest Rank Only", "highestOnly", "Shows one icon per type: the best rank you carry."),
        Dropdown("Tooltips", "tooltip", TOOLTIPS, TOOLTIP_ORDER,
            "Full: the item's tooltip. Name Only: just the item's name."))
    Row(Dropdown("Icon Shape", "shape", SHAPES, SHAPE_ORDER, "The shape of the button and every flyout icon."), nil)

    Header("BUTTON")
    local notCustom = function() return Get("mainIcon") ~= "custom" end
    Row(Dropdown("Button Icon", "mainIcon", MAIN_ICONS, MAIN_ICON_ORDER, "Last Applied shows whatever you last put on a weapon."),
        { type = "input", text = "Custom Icon", inputStyle = "popup", placeholder = "Icon name or file ID", inputWidth = 170,
          disabled = notCustom, disabledTooltip = "Button Icon: Custom",
          tooltip = "An icon name such as Ability_Rogue_Sprint, or a file ID.",
          getValue = function() return Get("customIcon") end, setValue = function(v) Set("customIcon", v or "") end })
    Row(Slider("Button Size", "size", SIZE_MIN, SIZE_MAX),
        Slider("Opacity", "opacity", 0.1, 1, 0.05, "Opacity of the button and flyout. Show Only on Mouseover fades up to this value."))
    Row(Toggle("Show Only on Mouseover", "mouseover", "Keeps the button invisible until the mouse is over it."), nil)

    Header("FLYOUT")
    Row(Dropdown("Flyout Direction", "direction", DIRECTIONS, DIRECTION_ORDER),
        Slider("Item Size", "itemSize", 16, 64))
    Row(Slider("Spacing", "spacing", 0, 10),
        Toggle("Flyout Background", "background", "Draws a themed panel behind the flyout's icons."))

    Header("BEHAVIOR")
    local notClick = function() return Get("openMode") ~= "click" end
    Row(Dropdown("Open On", "openMode", OPEN_MODES, OPEN_MODE_ORDER),
        Dropdown("After a Click", "clickClose", CLICK_CLOSES, CLICK_CLOSE_ORDER,
            "Stay Open: click the button again to close. Hide After Leaving: closes once the mouse leaves.",
            notClick, "Open On: Click"))
    Row(Slider("Open Delay (sec)", "openDelay", 0, 1, 0.05, nil,
            function() return Get("openMode") ~= "hover" end, "Open On: Hover"),
        Slider("Hide Delay (sec)", "closeDelay", 0, 2, 0.05, nil,
            function() return Get("openMode") == "click" and Get("clickClose") == "stay" end,
            "Open On: Hover, or After a Click: Hide After Leaving"))
    Row(Toggle("Close After Use", "closeOnUse", "Closes the flyout once you apply something."), nil)

    Header("ANIMATION")
    local instant = function() return Get("animation") == "instant" end
    Row(Dropdown("Animation", "animation", ANIMATIONS, ANIMATION_ORDER),
        Dropdown("Easing", "easing", EASING_NAMES, EASING_ORDER, nil, instant, "Animation"))
    Row(Slider("Duration (sec)", "duration", 0.05, 0.6, 0.05, nil, instant, "Animation"),
        Slider("Cascade Delay (sec)", "stagger", 0.01, 0.2, 0.01, "How long each icon waits after the one before it.",
            function() return Get("animation") ~= "cascade" end, "Animation: Cascade"))

    Header("HIGHLIGHT APPLIED")
    local glowOff = function() return not Get("applied") end
    Row(Toggle("Highlight Applied", "applied", "Makes whatever is on your weapons glow in the open flyout."),
        Color("Highlight Color", "glowColor", true, nil, glowOff, "Highlight Applied"))
    Row(Dropdown("Highlight Animation", "glowStyle", GLOW_STYLES, GLOW_STYLE_ORDER, nil, glowOff, "Highlight Applied"),
        Slider("Pulse Speed (sec)", "glowSpeed", 0.2, 3, 0.1, "Seconds for each fade, out or back. Higher is slower.",
            function() return not Get("applied") or Get("glowStyle") == "static" end, "Highlight Animation: Pulse"))

    Header("ITEM COUNT")
    local countOff = function() return not Get("showCount") end
    local why = "Show Item Counts"
    Row(Toggle("Show Item Counts", "showCount"),
        Dropdown("Count Position", "countPoint", COUNT_POINTS, COUNT_POINT_ORDER, nil, countOff, why))
    Row(Slider("Count Size", "countSize", 6, 24, 1, nil, countOff, why),
        Dropdown("Count Outline", "countOutline", OUTLINES, OUTLINE_ORDER, nil, countOff, why))
    Row(Slider("Count X Offset", "countX", -20, 20, 1, nil, countOff, why),
        Slider("Count Y Offset", "countY", -20, 20, 1, nil, countOff, why))
    Row(Color("Count Color", "countColor", false, nil, countOff, why), nil)

    Header("EFFECTS")
    local fxOff = function() return not Get("fx") end
    local fxWhy = "Enable Effects"
    Row(Toggle("Enable Effects", "fx"),
        Toggle("Effects Only on Hover", "bubblesOnHover", "Bubbles and sparkles show only while the mouse is over the dock.",
            fxOff, fxWhy))
    Row(Toggle("Effects Only When Applied", "bubblesOnApplied",
            "Bubbles show only while a poison is on a weapon, sparkles only while a stone or oil is.", fxOff, fxWhy),
        Dropdown("Applied On", "appliedHand", APPLIED_HANDS, APPLIED_HAND_ORDER,
            "Which weapon Effects Only When Applied looks at.",
            function() return not Get("fx") or not Get("bubblesOnApplied") end, "Effects Only When Applied"))
    Row(Slider("Splash Opacity", "splashAlpha", 0, 1, 0.05,
            "Droplets bursting from the button when you apply something. 0 turns it off.", fxOff, fxWhy), nil)
    Row(Color("Bubbles Color", "bubbleColor", true, "Venom bubbles rising from the button. Alpha 0 turns them off.",
            fxOff, fxWhy),
        Color("Sparkles Color", "sparkleColor", true, "Stars twinkling around the button. Alpha 0 turns them off.",
            fxOff, fxWhy))
    return math.abs(y)
end

-- What Restock.lua (loaded first) uses at run time.
ns.Decorate, ns.ApplyShape = Decorate, ApplyShape
ns.Particle, ns.Burst, ns.DROPLETS = Particle, Burst, DROPLETS
ns.LaunchBubble, ns.BUBBLES = LaunchBubble, BUBBLES
ns.GROUP_BY_NAME, ns.GROUP_OF_ITEM = GROUP_BY_NAME, GROUP_OF_ITEM
ns.SHAPES, ns.SHAPE_ORDER, ns.OUTLINES, ns.OUTLINE_ORDER = SHAPES, SHAPE_ORDER, OUTLINES, OUTLINE_ORDER
ns.db = function() return db end
ns.Skin = function() return skin end

EUI.RegisterPlugin(ADDON, {
    label = "Poisons",
    modules = { {
        key = "General", title = "Dock",
        description = "Hover or click the button to list your poisons, stones and oils. Left-click an item for your main hand, right-click for your off hand. Right-click the button to open these settings.",
        pages = { "General" },
        buildPage = BuildPage,
        onPageCacheRestore = function() RefreshEditor() end,
        onReset = function()
            local restock = db.restock   -- Restock.lua's settings; its own page resets them
            wipe(db)
            db.restock = restock
            InvalidateOrder()
            if main then SavedPoint() end
            Refresh(true)
            RefreshEditor()
            SyncBubbles()
        end,
    }, ns.RestockModule },   -- nil for non-rogues, which leaves just the General module
})

if EUI.RegisterSkin then
    EUI.RegisterSkin(ADDON, function(S)
        skin = S
        -- ponytail: OnLooksChanged fires on accent changes only; an eUI font change reaches the counts at the next Layout.
        if S.OnLooksChanged then
            S.OnLooksChanged(function()
                if main then StyleCounts() end
                if ns.RestockLayout then ns.RestockLayout() end   -- its counts use the eUI font too
            end)
        end
        if fly then
            S.Panel(fly.bg)
            fly.bg.plain:Hide()
            Layout()
        end
    end)
end

SLASH_ELLESMEREPOISONS1 = "/epoisons"
-- "/epoisons debug": what the dock sees in bags and on each weapon, for matching problems.
local function Show(v) return Readable(v) and tostring(v) or "secret" end

local function Debug()
    print("|cff74ff40Ellesmere Poisons|r bags:")
    for _, g in ipairs(GROUPS) do
        for i = 1, #g do
            local n = C_Item.GetItemCount(g[i])
            if n > 0 then print(("  %s  item %d  x%d  icon %s"):format(g.name, g[i], n, tostring(C_Item.GetItemIconByID(g[i])))) end
        end
    end
    local available = EachEnchant(function(slot, e, why)
        if not e then
            print("  " .. slot .. ": " .. why)
            return
        end
        print(("  %s: has %s  type %s  enchant %s  icon %s  left %s  kind %s"):format(slot, Show(e.hasEnchant),
            Show(e.enchantType), Show(e.enchantID), Show(e.enchantIconID), Show(e.timeLeft),
            Readable(e.enchantIconID) and KindsOfIcon(e.enchantIconID) or "secret"))
    end)
    if not available then print("  weapon enchant info is not available") end
end

SlashCmdList.ELLESMEREPOISONS = function(msg)
    if strtrim(msg or ""):lower() == "debug" then Debug() else EUI.OpenPlugin(ADDON) end
end

local events = CreateFrame("Frame")
local infoQueued = false   -- one Layout per burst of item data
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
events:RegisterEvent("WEAPON_ENCHANT_CHANGED")
events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
events:SetScript("OnEvent", function(_, event, arg, castGUID, spellID)
    if event == "PLAYER_LOGIN" then
        EllesmerePoisonsDB = EllesmerePoisonsDB or {}
        db = EllesmerePoisonsDB
        CreateDock()
        RegisterUnlock()
        if ns.RestockLogin then ns.RestockLogin() end
    elseif not main then
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        if progress ~= target then FinishAnimation() end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        Layout()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if GROUP_OF_ITEM[arg] and (requested[arg] or iconKindPartial ~= false) and not infoQueued then
            infoQueued = true
            C_Timer.After(0, function()
                infoQueued = false
                if iconKindPartial then iconKind = nil end
                readApplied = true
                RefreshEditor()
                for i = 1, shown do buttons[i].icon:SetTexture(C_Item.GetItemIconByID(buttons[i].itemID)) end
                main.icon:SetTexture(MainIconTexture())
                Refresh()
            end)
        end
    elseif event == "WEAPON_ENCHANT_CHANGED" or event == "UNIT_INVENTORY_CHANGED" then
        readApplied = true
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        if Readable(castGUID) and castGUID == dockCastGUID then dockCastGUID = nil end
        if Readable(spellID) and spellID == dockClickedSpell then dockClickedAt, dockClickedSpell = -math.huge, nil end
    elseif event == "UNIT_SPELLCAST_START" then
        if Readable(spellID) and Readable(castGUID) and spellID == dockClickedSpell
            and GetTime() - dockClickedAt < CLICK_WINDOW then
            dockCastGUID = castGUID
            dockClickedAt, dockClickedSpell = -math.huge, nil
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- ponytail: while casts are restricted the spell ID reads as secret, and nothing else names the cast then.
        -- Such an application gets no splash, Last Applied or Close After Use.
        local itemID = Readable(spellID) and spellItem[spellID]
        if itemID and spellID == dockClickedSpell and GetTime() - dockClickedAt < CLICK_WINDOW then
            dockCastGUID = Readable(castGUID) and castGUID or nil   -- instant: no START came first
            dockClickedAt, dockClickedSpell = -math.huge, nil
        end
        if itemID then OnApplied(itemID, Readable(castGUID) and castGUID or nil) end
    else
        if event == "PLAYER_REGEN_ENABLED" and positionPending then
            SavedPoint()
            pending = true   -- the Refresh below redoes the layout, flyout direction included
        end
        if event == "PLAYER_REGEN_ENABLED" and closeAfterCombat then
            closeAfterCombat = false
            CloseAfterUse()
        end
        if event == "BAG_UPDATE_DELAYED" or pending then
            Refresh()
            if editor.frame and editor.frame:IsVisible() then RefreshEditor() end
        end
    end
end)
