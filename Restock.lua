-- Restock: at a poison vendor, a column of buttons beside the merchant window refills each poison to a target.
-- Click a poison to buy its missing reagents, then again to craft your highest learned rank; click Flash Powder to buy it.
-- Mouse wheel changes a target, right-click opens the Restock page. Targets live on that page in EllesmereUI.
local ADDON, ns = ...
if select(2, UnitClass("player")) ~= "ROGUE" then return end
local EUI = _G.EllesmereUI
local L, Lf = EUI.L, EUI.Lf   -- type names are English keys; L shows them in the game's language

local POISONS_SKILL = 40   -- the Poisons profession's skill line
local DEATHWEED = 5173     -- only poison vendors sell it
local FLASH_POWDER = 5140
local FLASH = "Flash Powder"
local TYPES = { "Instant Poison", "Deadly Poison", "Crippling Poison", "Mind-numbing Poison", "Wound Poison", FLASH }
local STEP, MAX_TARGET = 5, 100
local WAIT_TRIES, WAIT_STEP = 30, 0.1   -- how long to wait for the Poisons window to be ready
local JOB_TIMEOUT = 10                  -- seconds a purchase may take to reach the bags
local RED, GREEN = { 1, 0.2, 0.33 }, { 0, 0.78, 0.13 }

local bar
local vendorOpen = false   -- between MERCHANT_SHOW and MERCHANT_CLOSED; MerchantFrame can still read as shown after the close
local editor   -- the Restock page's button editor, made on first use (see Editor)
local Relabel = function() end   -- relabels the shown buttons; set once they exist
local UNLOCK_KEY = ADDON .. "Restock"

local function RefreshEditor()
    if editor and editor.frame and editor.frame:IsVisible() then editor.Refresh() end
end

-- The Restock page lists learned poisons only, so a change in what is learned drops its cached build and rebuilds the open page.
local function LearnedChanged()
    local key = EUI.GetPluginModuleKey(ADDON, "Restock")
    if key and EUI.InvalidateModulePageCache then EUI:InvalidateModulePageCache(key) end
    EUI:RefreshPage(true)   -- eUI defers this while the panel is closed
end

local function Say(msg) print("|cff74ff40Ellesmere Poisons:|r " .. msg) end

-- Everything Restock saves, in one table of EllesmerePoisonsDB so General's reset can keep it whole.
-- off: the Enable toggle unticked. targets: type name -> how many to keep. pos: the bar's Unlock Mode spot.
-- order: button order by type name (missing names follow in TYPES order). hidden: type name -> true for a hidden button.
-- The bar's looks (see LOOKS) sit beside these, unset until changed.
local R

-- Learned poisons, worked out from your recipe spells (ReadRanks), so nothing about them is saved.
-- type name -> { recipe, item, rank } for its highest learned rank; nil when none is learned.
local ranks = {}

local function Init()
    local db = ns.db()
    if type(db.restock) ~= "table" then db.restock = {} end
    R = db.restock
    R.targets = R.targets or {}
    R.ranks = nil   -- an earlier version saved them
end

-- The buttons' order: the saved one, minus unknown names, then any type it lacks in TYPES order.
local function Ordered()
    local out, seen = {}, {}
    for _, name in ipairs(R.order or {}) do
        if tContains(TYPES, name) and not seen[name] then out[#out + 1], seen[name] = name, true end
    end
    for _, name in ipairs(TYPES) do
        if not seen[name] then out[#out + 1] = name end
    end
    return out
end

-- The bar's own looks, separate from the dock's.
local LOOKS = {
    layout = "vertical", size = 32, spacing = 2, shape = "cropped", background = true,
    countSize = 11, countOutline = "OUTLINE", countColor = { r = 1, g = 1, b = 1 },
    splash = true, splashColor = { r = 0.45, g = 1, b = 0.25, a = 0.9 },
}
local function Look(key)
    local v = R[key]
    if v == nil then return LOOKS[key] end
    return v
end

local function Target(name) return R.targets[name] or 0 end

-- A type's icon: its best known rank, else its highest rank.
local function ButtonIcon(name)
    if name == FLASH then return C_Item.GetItemIconByID(FLASH_POWDER) end
    local r, g = ranks[name], ns.GROUP_BY_NAME[name]
    return C_Item.GetItemIconByID(r and r.item or g[#g])
end

-- Flash Powder, and every poison you have learned.
local function Known(name) return name == FLASH or ranks[name] ~= nil end

-- The types that are known, in bar order.
local function KnownOrdered()
    local out = {}
    for _, name in ipairs(Ordered()) do
        if Known(name) then out[#out + 1] = name end
    end
    return out
end

-- Only the rank it would craft counts, so leftovers of a lower rank never satisfy the target.
local function Have(name)
    if name == FLASH then return C_Item.GetItemCount(FLASH_POWDER) end
    local r = ranks[name]
    return r and C_Item.GetItemCount(r.item) or 0
end

-- Your own Poisons window, not a linked or guild one, whose recipes may still be loading.
local function PoisonsShown()
    if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then return false end
    if C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild() or C_TradeSkillUI.IsTradeSkillGuildMember() then
        return false
    end
    local info = C_TradeSkillUI.GetBaseProfessionInfo()
    return info ~= nil and info.professionID == POISONS_SKILL
end

local function WindowReady() return PoisonsShown() and C_TradeSkillUI.IsTradeSkillReady() end

-- Each poison's recipe spells, lowest rank first, in the order of its items in EllesmerePoisons.lua's GROUPS.
-- A recipe's ID is its spell's, so CraftRecipe takes these as they are. Learned recipes report through IsPlayerSpell.
local RECIPE_SPELLS = {
    ["Instant Poison"] = { 8681, 8687, 8691, 11341, 11342, 11343 },
    ["Deadly Poison"] = { 2835, 2837, 11357, 11358, 25347 },
    ["Crippling Poison"] = { 3420, 3421 },
    ["Mind-numbing Poison"] = { 5763, 8694, 11400 },
    ["Wound Poison"] = { 13220, 13228, 13229, 13230 },
}

-- recipe spell -> poison type, for telling which button a finished craft belongs to
local NAME_OF_RECIPE = {}
for name, spells in pairs(RECIPE_SPELLS) do
    for _, id in ipairs(spells) do NAME_OF_RECIPE[id] = name end
end

-- Works out each poison's best learned rank afresh. Returns whether any rank changed, and whether the set of learned types did.
local function ReadRanks()
    local changed, learnedChanged = false, false
    for name, spells in pairs(RECIPE_SPELLS) do
        local found
        for i = #spells, 1, -1 do
            if IsPlayerSpell(spells[i]) then
                found = i
                break
            end
        end
        local had = ranks[name]
        if (had and had.rank) ~= found then
            changed = true
            learnedChanged = learnedChanged or (had == nil) ~= (found == nil)
            ranks[name] = found and { recipe = spells[found], item = ns.GROUP_BY_NAME[name][found], rank = found } or nil
        end
    end
    return changed, learnedChanged
end

local LayoutBar
local opening = false   -- a click is waiting for the Poisons window

-- Runs fn once the Poisons window is ready, opening it first if needed: crafting works through it.
local function WithWindow(fn)
    local tries, seen = 0, false
    opening = true
    local function wait()
        if WindowReady() then
            opening = false
            fn()
            Relabel()   -- fn may have ended without changing anything, but no longer opening must show
        elseif seen and not ProfessionsFrame:IsShown() then
            opening = false   -- closed while it loaded: the player changed their mind
            Relabel()
        elseif tries < WAIT_TRIES then
            seen = seen or (ProfessionsFrame and ProfessionsFrame:IsShown()) or false
            tries = tries + 1
            C_Timer.After(WAIT_STEP, wait)
        else
            opening = false
            Say(L("Could not open the Poisons window."))
            Relabel()
        end
    end
    -- Opening it again while it loads could toggle it closed.
    if not PoisonsShown() then C_TradeSkillUI.OpenTradeSkill(POISONS_SKILL) end
    wait()
end

local unlocked = false   -- an Unlock Mode session is open, as its listener reports (it stays open through combat)

local function MerchantIndex(itemID)
    for i = 1, GetMerchantNumItems() do
        if GetMerchantItemID(i) == itemID then return i end
    end
end

-- Buys every item of `wants` ({ [itemID] = count }) in the largest lots the vendor sells.
-- Buys nothing and returns the reason when the vendor is gone, lacks one of them, or you lack the gold.
-- ponytail: bag space and limited stock are not checked; such a purchase just never arrives (the job times out).
local function BuyAll(wants)
    if not vendorOpen then return L("The vendor closed.") end
    local plan, cost = {}, 0
    for id, count in pairs(wants) do
        local i = MerchantIndex(id)
        local info = i and C_MerchantFrame.GetItemInfo(i)
        if not info then
            local item = C_Item.GetItemNameByID(id)
            return item and Lf("This vendor does not sell %s.", item) or L("This vendor does not sell a reagent it needs.")
        end
        cost = cost + info.price * count / math.max(info.stackCount, 1)
        plan[#plan + 1] = { i, count }
    end
    if cost > GetMoney() then return L("Not enough gold.") end
    for _, p in ipairs(plan) do
        local i, count = p[1], p[2]
        local lot = math.max(GetMerchantItemMaxStack(i) or 1, 1)
        while count > 0 do
            local n = math.min(count, lot)
            BuyMerchantItem(i, n)
            count = count - n
        end
    end
end

-- A purchase on its way to the bags: { name, need = { [itemID] = count the bags must hold } }. It holds clicks until it lands.
-- `need` is the craft's total reagents, which using one poison never lowers.
-- For Flash Powder it is the whole purchase, so a second click cannot buy it again.
-- A Vanish while it lands can keep the count short; the timeout then just lets clicks through.
local job
-- The game starts a craft only from a click, never from a timer or an event. So a poison whose reagents are ready
-- (bought, or the Poisons window had to open first) glows and waits for the click that crafts it.
local ready = {}   -- poison name -> true while it waits for that click

local function Arrived(j)
    for id, n in pairs(j.need) do
        if C_Item.GetItemCount(id) < n then return false end
    end
    return true
end

local function Casting() return UnitCastingInfo("player") or UnitChannelInfo("player") end

-- Clicks wait this long after a craft is sent (before its cast starts) and after its casts end (before its poisons are counted).
local SETTLE = 1.5
local START_WAIT = 3   -- seconds a sent craft may take to start its first cast before it counts as refused
local settleUntil = 0
local crafting = false   -- a craft was sent and its series has not ended (UPDATE_TRADESKILL_CAST_STOPPED)
local castStarted = false   -- the sent craft's first cast began
local craftName, craftRecipe -- the poison and recipe of the craft that was sent
local craftToken             -- the craft the start failsafe belongs to

-- Holds clicks for SETTLE, then relabels so an open tooltip stops saying "Restocking...".
local function Settle()
    settleUntil = math.max(settleUntil, GetTime() + SETTLE)
    C_Timer.After(SETTLE + WAIT_STEP, function() Relabel() end)
end

-- `why` alone when the click cannot craft yet; `whyCraft` (the same news, asking for the click) once it can.
local function WaitForClick(name, why, whyCraft)
    if not vendorOpen then return end   -- the bar is gone with the vendor; the bought reagents stay for the next visit
    -- A glow promises the click crafts, which needs the window; closed, the next click reopens it first.
    if not WindowReady() or unlocked then
        Say(why)
        Relabel()
        return
    end
    ready[name] = true
    Say(whyCraft)
    Relabel()
end

-- Ends the job once its purchase is all in the bags; a poison then waits for the click that crafts it.
local function CheckJob()
    if not (job and Arrived(job)) then return end
    local name = job.name
    job = nil
    if name ~= FLASH then WaitForClick(name, Lf("Reagents for %s are in.", L(name)),
        Lf("Reagents for %s are in. Click %s again to craft.", L(name), L(name))) end
end

-- Only works inside a click (see `ready`).
-- The glow stays until the first cast starts, so a craft the game refuses (moving, another cast) can be clicked again.
local function Craft(name, recipe, casts)
    Settle()
    crafting, castStarted, craftName, craftRecipe = true, false, name, recipe
    local mine = {}
    craftToken = mine
    C_TradeSkillUI.CraftRecipe(recipe, casts)
    -- A refused craft never casts, so no series end comes to clear the flag.
    -- Another cast or channel then (a channel ends without a cast stop) only postpones the check.
    local function check()
        if craftToken ~= mine or not crafting or castStarted then return end
        if Casting() then
            C_Timer.After(WAIT_STEP * 5, check)
            return
        end
        crafting = false
        Say(Lf("The %s craft did not start. Click it again to craft.", L(name)))
        Relabel()
    end
    C_Timer.After(START_WAIT, check)
end

-- What reaching the target takes: wants (itemID -> count to buy), need (itemID -> count the bags must hold),
-- and for a poison its recipe and casts. Nil when the recipe cannot be read.
local function Plan(name, missing)
    local wants, need = {}, {}
    if name == FLASH then
        wants[FLASH_POWDER] = missing
        need[FLASH_POWDER] = C_Item.GetItemCount(FLASH_POWDER) + missing
        return wants, need
    end
    local r = ranks[name]
    local s = C_TradeSkillUI.GetRecipeSchematic(r.recipe, false)
    if not s then return end
    local casts = math.ceil(missing / math.max(s.quantityMin or 1, 1))
    for _, slot in ipairs(s.reagentSlotSchematics or {}) do
        local reagent = slot.required ~= false and slot.reagents and slot.reagents[1]
        if reagent and reagent.itemID then
            local id = reagent.itemID
            need[id] = slot.quantityRequired * casts
            if need[id] > C_Item.GetItemCount(id) then wants[id] = need[id] - C_Item.GetItemCount(id) end
        end
    end
    return wants, need, r.recipe, casts
end

-- Brings a type up to its target: buys what is missing, or crafts when everything is in the bags.
-- `inClick` says this runs inside the click itself, the only place a craft can start.
-- ponytail: one purchase at a time; clicks wait until it lands. A queue would chain them.
local function Restock(name, inClick)
    if Target(name) == 0 then
        Say(Lf("%s has no target. Set one with the mouse wheel.", L(name)))
        return
    end
    if name ~= FLASH and not ranks[name] then
        Say(Lf("%s is not learned.", L(name)))
        return
    end
    local missing = Target(name) - Have(name)
    if missing <= 0 then
        Say(Lf("%s is already stocked.", L(name)))
        return
    end
    local wants, need, recipe, casts = Plan(name, missing)
    if not wants then
        Say(Lf("Could not read the %s recipe.", L(name)))
        return
    end
    if not next(wants) and recipe then   -- Flash Powder always has something to buy
        if not inClick and not vendorOpen then return end   -- the vendor closed while the window loaded: nothing to click
        C_TradeSkillUI.OpenRecipe(recipe)   -- shows what is being crafted (see the purchase below)
        if inClick then
            Craft(name, recipe, casts)
        else
            WaitForClick(name, L("The Poisons window is open."), Lf("The Poisons window is open. Click %s again to craft.", L(name)))
        end
        return
    end
    local why = BuyAll(wants)
    if why then
        Say(why)
        return
    end
    -- Shows what the reagents were bought for. Blizzard's UI does the selecting, so nothing is tainted.
    if recipe then C_TradeSkillUI.OpenRecipe(recipe) end
    local mine = { name = name, need = need }
    job = mine
    C_Timer.After(JOB_TIMEOUT, function()
        if job ~= mine then return end
        if Arrived(mine) then   -- the last item may have been counted after the last bag update
            CheckJob()
            return
        end
        job = nil
        if name ~= FLASH then Say(Lf("The purchase for %s did not arrive.", L(name))) end
        Relabel()
    end)
end

-- Includes the gaps between the casts of a multi-cast craft.
local function Busy()
    return job or opening or crafting or Casting() or C_TradeSkillUI.GetRemainingRecasts() > 0 or GetTime() < settleUntil
end

local function OnClick(self, button)
    if button == "RightButton" then
        EUI.OpenPlugin(ADDON, "Restock")
    elseif unlocked then
        return   -- a preview: away from a vendor there is nothing to buy
    elseif Busy() then
        Say(L("Still restocking."))
    elseif self.name == FLASH or Target(self.name) == 0 or Have(self.name) >= Target(self.name) or WindowReady() then
        Restock(self.name, true)
    else
        -- Crafting needs the Poisons window. Opening it takes a moment, past this click, so a craft then waits for the next one.
        WithWindow(function()
            if not unlocked then Restock(self.name, false) end   -- Unlock Mode may have opened while the window loaded
        end)
    end
end

local function Label(b)
    local have, target = Have(b.name), Target(b.name)
    local c, tc = have < target and RED or GREEN, Look("countColor")
    b.target:SetText(target)
    b.target:SetTextColor(tc.r, tc.g, tc.b)   -- the have count stays red or green
    b.count:SetText(have)
    b.count:SetTextColor(c[1], c[2], c[3])
    -- The glow of a poison waiting for the click that crafts it; stocked by other means, it stops waiting.
    local glow = ready[b.name] and have < target or false
    if not glow then ready[b.name] = nil end
    if glow ~= (b.glowing or false) then   -- only on a change, so a hover highlight is left alone
        b.glowing = glow
        if glow then b:LockHighlight() else b:UnlockHighlight() end
    end
end

local function OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L(self.name), 1, 1, 1)
    local r = ranks[self.name]
    local makes = r and C_Item.GetItemNameByID(r.item)
    if makes then GameTooltip:AddLine(Lf("Makes %s", makes), 0.6, 0.85, 1) end
    GameTooltip:AddLine(Lf("Have %d of %d", Have(self.name), Target(self.name)), 1, 0.82, 0)
    local missing = Target(self.name) - Have(self.name)
    -- The same order OnClick and Restock decide in, so the line says what a click would do.
    if unlocked then
        GameTooltip:AddLine(L("Preview while Unlock Mode is open"), 0.7, 0.7, 0.7)
    elseif Busy() then
        GameTooltip:AddLine(L("Restocking..."), 0.7, 0.7, 0.7)
    elseif Target(self.name) == 0 then
        GameTooltip:AddLine(L("No target yet"), 1, 0.2, 0.33)
    elseif missing <= 0 then
        GameTooltip:AddLine(L("Stocked"), 0, 0.78, 0.13)
    elseif self.name == FLASH then
        GameTooltip:AddLine(L("Click to buy up to the target"), 0.7, 0.7, 0.7)
    else
        -- The recipe may be unreadable before the Poisons window first opened; the plain line covers that.
        local wants = ranks[self.name] and Plan(self.name, missing)
        if not wants then
            GameTooltip:AddLine(L("Click to restock up to the target"), 0.7, 0.7, 0.7)
        elseif next(wants) then
            GameTooltip:AddLine(L("Click to buy reagents"), 0.7, 0.7, 0.7)
        elseif WindowReady() then
            GameTooltip:AddLine(L("Click to craft"), 0.45, 1, 0.25)
        else
            -- Crafting works only from a click with the Poisons window open, so the first click opens it.
            GameTooltip:AddLine(L("Click to open the Poisons window"), 0.7, 0.7, 0.7)
        end
    end
    GameTooltip:AddLine(L("Mouse wheel to change the target, right-click for settings"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function OnMouseWheel(self, delta)
    R.targets[self.name] = Clamp(Target(self.name) + delta * STEP, 0, MAX_TARGET)
    Label(self)
    OnEnter(self)
    EUI:RefreshPage()   -- the open Restock page's sliders; deferred by eUI while the panel is closed
end

local buttons = {}

Relabel = function()
    for _, b in pairs(buttons) do
        if b:IsShown() then
            Label(b)
            if GameTooltip:IsOwned(b) then OnEnter(b) end
        end
    end
end

-- Craft effects in the dock's style: bubbles rising from a poison's button when its craft starts,
-- and the dock's droplet burst for each poison made. Their own particles, made on first use.
local droplets, bubbles
local BUBBLE_STAGGER = 0.15   -- seconds between the start's bubbles

-- The button to play an effect on and the effect's color, or nil when effects are off or it is not shown.
local function EffectTarget(name)
    local b, c = buttons[name], Look("splashColor")
    if not (Look("splash") and b and b:IsVisible() and (c.a or 1) > 0) then return end
    if not droplets then
        local layer = CreateFrame("Frame", nil, bar)
        layer:SetAllPoints()
        layer:SetFrameLevel(bar:GetFrameLevel() + 20)   -- above the buttons
        droplets, bubbles = {}, {}
        for i = 1, ns.DROPLETS do droplets[i] = ns.Particle(layer, 3 + math.random() * 2) end
        for i = 1, ns.BUBBLES do bubbles[i] = ns.Particle(layer, 3 + math.random() * 3) end
    end
    return b, c
end

local function CraftSplash(name)
    local b, c = EffectTarget(name)
    if b then ns.Burst(droplets, b, c, c.a or 1) end
end

local function CraftBubbles(name)
    local b, c = EffectTarget(name)
    if not b then return end
    for i, f in ipairs(bubbles) do
        f.ag:Stop()
        f.tex:SetVertexColor(c.r, c.g, c.b)
        f.tex:SetAlpha(c.a or 1)
        C_Timer.After((i - 1) * BUBBLE_STAGGER, function()
            if b:IsVisible() then ns.LaunchBubble(f, b) end
        end)
    end
end

local function MakeButton(name)
    local b = CreateFrame("Button", nil, bar)
    b.name = name
    ns.Decorate(b)
    b.target = b.edge:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.target:SetPoint("TOPLEFT", 2, -2)
    b.count = b.edge:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", OnClick)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:EnableMouseWheel(true)
    b:SetScript("OnMouseWheel", OnMouseWheel)
    buttons[name] = b
    return b
end

-- What the open vendor sells that decides the bar's buttons: poisons (Deathweed) and Flash Powder, as 1 and 2.
local function Sells()
    return (MerchantIndex(DEATHWEED) and 1 or 0) + (MerchantIndex(FLASH_POWDER) and 2 or 0)
end

-- A poison shows at a poison vendor unless the Poisons window said it is not learned; Flash Powder wherever it is sold.
-- Unlock Mode previews every button that could show, wherever you are.
-- `preview` forces the Unlock Mode layout (login sizes the bar that way for its mover).
LayoutBar = function(preview)
    local size, gap = Look("size"), Look("spacing")
    local across = Look("layout") == "horizontal"
    preview = preview or unlocked
    bar.sells = Sells()
    local poisons = preview or bar.sells % 2 == 1
    local skin = ns.Skin()
    local font, fontSize = skin and skin.GetFont() or STANDARD_TEXT_FONT, Look("countSize")
    local outline = Look("countOutline")
    local flags = (outline == "OUTLINE" or outline == "THICKOUTLINE") and outline or ""
    local shadow = outline == "SHADOW" and 1 or 0
    local n = 0
    for _, name in ipairs(Ordered()) do
        local b = buttons[name] or MakeButton(name)
        local on
        if name == FLASH then on = preview or bar.sells >= 2 else on = poisons and Known(name) end
        on = on and not (R.hidden and R.hidden[name])
        b:SetShown(on)
        if on then
            b.icon:SetTexture(ButtonIcon(name))
            b:SetSize(size, size)
            ns.ApplyShape(b, Look("shape"))
            -- The user's eUI font, like the flyout's counts.
            for _, fs in ipairs({ b.target, b.count }) do
                fs:SetFont(font, fontSize, flags)
                fs:SetShadowColor(0, 0, 0, 1)
                fs:SetShadowOffset(shadow, -shadow)
            end
            b:ClearAllPoints()
            -- Spacing only between buttons, along the layout; none around the edges.
            local step = n * (size + gap)
            if across then b:SetPoint("TOPLEFT", bar, "TOPLEFT", step, 0) else b:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -step) end
            Label(b)
            n = n + 1
        end
    end
    local long, short = math.max(n * (size + gap) - gap, 0), size
    if across then bar:SetSize(long, short) else bar:SetSize(short, long) end
    bar.bg:SetShown(Look("background"))
    bar:SetShown(n > 0)
end

local function Enabled() return not R.off and IsPlayerSpell(2842) end   -- 2842: the Poisons spell

-- The default spot (beside the merchant window) as an offset from UIParent's top left: the open window's top right,
-- or, while it is closed, where the game opens it: the left panel slot, LEFT_OFFSET across and TOP_OFFSET down.
local function DefaultSpot()
    local s = MerchantFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local right, top = MerchantFrame:GetRight(), MerchantFrame:GetTop()
    if vendorOpen and right and top then
        return right * s + 2, top * s - UIParent:GetHeight()
    end
    return GetUIPanelLayoutAttribute("LEFT_OFFSET") + MerchantFrame:GetWidth() * s + 2, GetUIPanelLayoutAttribute("TOP_OFFSET")
end

-- Its own spot once moved in Unlock Mode, else beside the merchant window.
-- During Unlock Mode an unmoved bar is pinned to the default spot on screen: eUI places the mover once, and a
-- merchant window opening mid-session would otherwise carry the bar away from it.
local pinX, pinY   -- where an unmoved bar is pinned for the Unlock session (PlaceBar), as loadPos reports it

local function PlaceBar()
    local p = R.pos
    bar:ClearAllPoints()
    if p then
        bar:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    elseif unlocked then
        pinX, pinY = DefaultSpot()
        bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pinX, pinY)
    else
        bar:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 2, 0)
    end
end

local LAYOUTS = { vertical = "Vertical", horizontal = "Horizontal" }
local LAYOUT_ORDER = { "vertical", "horizontal" }

-- Shown at a vendor or in Unlock Mode. The eUI skin may register after login, so it is applied on first show.
local function UpdateBar()
    local skin = ns.Skin()
    if skin and not bar.skinned then
        skin.Panel(bar.bg)
        bar.bg.plain:Hide()
        bar.skinned = true
    end
    if Enabled() and (vendorOpen or unlocked) then
        LayoutBar()
    else
        bar:Hide()
    end
end

-- A setting changed: re-lay the bar where it may show, which also brings back one that had no buttons.
local function Relayout()
    if bar then UpdateBar() end
end


-- How far across and up a point sits on a frame.
local function Fraction(point)
    local fx = point:find("LEFT") and 0 or point:find("RIGHT") and 1 or 0.5
    local fy = point:find("BOTTOM") and 0 or point:find("TOP") and 1 or 0.5
    return fx, fy
end

-- A spot on UIParent, as the bar's top left corner.
-- The column grows down from its top, so a top left spot keeps the first button where it was placed at every vendor.
local moverW, moverH   -- the bar's size when the current Unlock Mode session opened

local function TopLeft(point, relPoint, x, y)
    local px, py = Fraction(point)
    local rx, ry = Fraction(relPoint)
    local w, h = moverW or bar:GetWidth(), moverH or bar:GetHeight()
    local left = rx * UIParent:GetWidth() + x - px * w
    local top = ry * UIParent:GetHeight() + y + (1 - py) * h
    return { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = left, y = top }
end

-- Called by EllesmerePoisons.lua once its settings are loaded.
function ns.RestockLogin()
    Init()
    ReadRanks()
    bar = CreateFrame("Frame", nil, UIParent)
    bar:SetFrameStrata("HIGH")
    bar:SetClampedToScreen(true)
    bar:Hide()
    -- Its own frame, so Background can hide it whether or not the eUI skin dressed it.
    bar.bg = CreateFrame("Frame", nil, bar)
    bar.bg:SetAllPoints()
    bar.bg:SetFrameLevel(bar:GetFrameLevel())
    bar.bg.plain = bar.bg:CreateTexture(nil, "BACKGROUND")
    bar.bg.plain:SetAllPoints()
    bar.bg.plain:SetColorTexture(0.05, 0.05, 0.05, 0.85)
    PlaceBar()
    LayoutBar(true)   -- Unlock Mode builds its mover from this size before the listener lays the bar out
    bar:Hide()
    EUI:RegisterUnlockElements({
        EUI.MakeUnlockElement({
            key = UNLOCK_KEY, label = "Restock Buttons", group = "Poisons", order = 901, noResize = true,
            -- One spot for every spec: spec layouts harvest loadPos during a session too (Save & Exit, a spec change),
            -- which would bank the unmoved bar's session-only spot and later pin it there.
            noSpecLayout = true,
            isHidden = function() return not Enabled() end,
            getFrame = function() return Enabled() and bar or nil end,
            getSize = function() return bar:GetWidth(), bar:GetHeight() end,
            savePos = function(_, point, relPoint, x, y)
                if point then R.pos = TopLeft(point, relPoint or point, x, y) end
            end,
            loadPos = function()
                local p = R.pos
                if p then return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y } end
                -- Unmoved, the bar hangs off the merchant window. During an Unlock session report its pinned spot:
                -- without one eUI reads the anchor's offsets as UIParent ones and a keyboard nudge throws the bar to
                -- the top right. Only then: eUI treats any answer as a saved spot (the session's cancel snapshot, its
                -- re-applies after zone changes, spec layouts) and would stop the bar following the merchant window.
                -- The pin, not a fresh DefaultSpot: a vendor opening or closing mid-session would move the answer.
                if unlocked and pinX then
                    return { point = "TOPLEFT", relPoint = "TOPLEFT", x = pinX, y = pinY }
                end
            end,
            clearPos = function()
                R.pos = nil
                PlaceBar()
            end,
            applyPos = PlaceBar,
        }),
    }, ADDON)
    EUI:RegisterUnlockModeListener(UNLOCK_KEY, function(active)
        unlocked = active == true
        PlaceBar()   -- pins an unmoved bar for the session, or puts it back by the merchant window after
        UpdateBar()
        -- eUI builds the mover from this size once the listeners ran, and cannot resize it during the session
        -- (NotifyElementResized waits for Unlock Mode to close). Saves convert against it, so the spot does not drift.
        -- ponytail: a layout change made during the session reaches the mover when Unlock Mode next opens.
        moverW, moverH = unlocked and bar:GetWidth() or nil, unlocked and bar:GetHeight() or nil
    end)
    ns.ElementOptions(UNLOCK_KEY, "Restock", "Restock", "RESTOCK AT VENDORS")
end

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:RegisterEvent("MERCHANT_UPDATE")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
events:RegisterEvent("UPDATE_TRADESKILL_CAST_STOPPED")
events:RegisterEvent("TRADE_SKILL_CLOSE")
events:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
events:SetScript("OnEvent", function(_, event, recipeID, _, spellID)
    if not bar then
        return
    elseif event == "TRADE_SKILL_CLOSE" then
        -- A glow promises the click crafts, which needs the window; the next click reopens it and glows again.
        wipe(ready)
        Relabel()   -- also turns an open tooltip's "Click to craft" back into opening the window
    elseif event == "TRADE_SKILL_LIST_UPDATE" then
        Relabel()   -- the window finished loading: an open tooltip can now say "Click to craft"
    elseif event == "UNIT_SPELLCAST_START" then
        -- The craft's own cast: a refused craft followed by some other cast must not count as started.
        -- A spell ID hidden as a secret value cannot be compared; that cast follows the craft just sent, so it counts.
        local secret = issecretvalue and issecretvalue(spellID)
        if crafting and not castStarted and (secret or spellID == craftRecipe) then
            castStarted = true
            ready[craftName] = nil
            CraftBubbles(craftName)
        end
        Relabel()   -- any cast makes clicks wait, so an open tooltip says so
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Every poison made, by Restock or by hand in the Poisons window, splashes on its button.
        local name = not (issecretvalue and issecretvalue(spellID)) and NAME_OF_RECIPE[spellID]
        if name then CraftSplash(name) end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        Relabel()
    elseif event == "UPDATE_TRADESKILL_CAST_STOPPED" or event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        -- The series ends with the game's own event, with an interrupted or failed cast of it,
        -- or with a cast stop and no casts left. Its poisons are counted shortly after.
        -- A cast event counts only once the craft's own cast began; before that it is some other spell.
        -- Only the craft's own spell: another spell failing mid-series (pressed during a cast) must not end it.
        local mine = (issecretvalue and issecretvalue(spellID)) or spellID == craftRecipe
        local ends = event == "UPDATE_TRADESKILL_CAST_STOPPED"
            or (mine and castStarted and (event ~= "UNIT_SPELLCAST_STOP" or C_TradeSkillUI.GetRemainingRecasts() == 0))
        if crafting and ends then
            crafting = false
            Settle()
        elseif crafting and mine and not castStarted and event == "UNIT_SPELLCAST_FAILED" then
            -- Refused before it cast (moving, cooldown): no need to wait out START_WAIT. The glow stays for another click.
            crafting = false
            Say(Lf("The %s craft did not start. Click it again to craft.", L(craftName)))
        end
        Relabel()
    elseif event == "MERCHANT_SHOW" then
        vendorOpen = true
        UpdateBar()
    elseif event == "MERCHANT_UPDATE" then
        -- The list can still be loading at MERCHANT_SHOW; each purchase also fires this, and only a change in what is sold relays.
        if vendorOpen and Enabled() and bar.sells ~= Sells() then UpdateBar() end
    elseif event == "MERCHANT_CLOSED" then
        vendorOpen = false
        wipe(ready)
        Relabel()   -- the bar may stay up in Unlock Mode
        bar.sells = nil   -- the next vendor's first update always lays the bar out
        -- A purchase already made still arrives, so the job carries on.
        if not unlocked then bar:Hide() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- An icon that was not cached yet; recipeID here is the item.
        local g = ns.GROUP_OF_ITEM[recipeID]
        if recipeID == FLASH_POWDER or (g and g.kind == "poison") then
            RefreshEditor()
            for name, b in pairs(buttons) do b.icon:SetTexture(ButtonIcon(name)) end
        end
    elseif event == "SPELLS_CHANGED" then
        -- Learning a recipe changes your spells; this fires after the spellbook has it, so the read sees it.
        local changed, learnedChanged = ReadRanks()
        if changed then
            RefreshEditor()   -- its icons show each type's best rank
            if learnedChanged then LearnedChanged() end
            Relayout()   -- through UpdateBar, so a bar that had no buttons comes back
        end
    else
        CheckJob()   -- a purchase can land after the vendor closed
        Relabel()
    end
end)



-- The button editor: every type, in bar order. Made on first use, since EllesmerePoisons.lua (with ns.NewEditor) loads after this file.
local function Editor()
    editor = editor or ns.NewEditor({
        list = KnownOrdered,
        icon = ButtonIcon,
        label = function(name) return name end,
        isHidden = function(name) return R.hidden and R.hidden[name] or false end,
        toggle = function(name)
            R.hidden = R.hidden or {}
            R.hidden[name] = not R.hidden[name] or nil
            Relayout()
        end,
        -- `to` is a slot among the listed types; unlearned ones keep their places in the full order.
        move = function(name, to)
            local shown = KnownOrdered()
            local from = tIndexOf(shown, name)
            if not from then return end   -- no longer listed (just read as unlearned)
            table.remove(shown, from)
            table.insert(shown, Clamp(to, 1, #shown + 1), name)
            local names, k = {}, 0
            for _, n in ipairs(Ordered()) do
                if Known(n) then
                    k = k + 1
                    names[#names + 1] = shown[k]
                else
                    names[#names + 1] = n
                end
            end
            R.order = names
            Relayout()
        end,
        hint = "Drag to reorder, click to hide or show",
        empty = "",
        shape = function() return Look("shape") end,
        })
    return editor
end

local function BuildPage(_, parent, yOffset)
    local W = EUI.Widgets
    local y = yOffset
    local _, h = W:SectionHeader(parent, "BUTTONS", y)
    y = y - h
    if EUI.IsSearchPrebuild and EUI.IsSearchPrebuild() then
        y = y - ns.EDITOR_HEIGHT
    else
        y = y - Editor().Build(parent, y)
    end
    _, h = W:SectionHeader(parent, "RESTOCK AT VENDORS", y)
    y = y - h
    local off = function() return R.off == true end
    local function Slider(name)
        return { type = "slider", text = name, min = 0, max = MAX_TARGET, step = STEP, disabled = off, disabledTooltip = "Enable",
            tooltip = name == FLASH and "How many to keep. Clicking it at a vendor buys up to this."
                or "How many to keep. Clicking it at a poison vendor restocks up to this.",
            getValue = function() return Target(name) end,
            setValue = function(v)
                R.targets[name] = v
                if bar and bar:IsShown() then LayoutBar() end
            end }
    end
    _, h = W:DualRow(parent, y, { type = "toggle", text = "Enable",
        tooltip = "Shows restock buttons beside the merchant window at poison and reagent vendors.",
        getValue = function() return not R.off end,
        setValue = function(v)
            R.off = not v or nil
            UpdateBar()
            EUI:RefreshPage()
        end }, nil)
    y = y - h

    local function SetLook(key, v)
        R[key] = v
        Relayout()
        if key == "shape" and editor then editor.Refresh() end
    end
    local function LookSlider(text, key, min, max, step, tip)
        return { type = "slider", text = text, min = min, max = max, step = step or 1, tooltip = tip,
            getValue = function() return Look(key) end, setValue = function(v) SetLook(key, v) end }
    end
    local function LookDropdown(text, key, values, order, tip)
        return { type = "dropdown", text = text, values = values, order = order, tooltip = tip,
            getValue = function() return Look(key) end, setValue = function(v) SetLook(key, v) end }
    end
    local function Row(left, right)
        _, h = W:DualRow(parent, y, left, right)
        y = y - h
    end

    _, h = W:SectionHeader(parent, "LAYOUT", y)
    y = y - h
    Row(LookDropdown("Layout", "layout", LAYOUTS, LAYOUT_ORDER, "Vertical: a column. Horizontal: a row."),
        LookDropdown("Icon Shape", "shape", ns.SHAPES, ns.SHAPE_ORDER))
    Row(LookSlider("Button Size", "size", 16, 64), LookSlider("Spacing", "spacing", 0, 10, 1, "Gap between the buttons."))
    Row({ type = "toggle", text = "Background", tooltip = "Draws a themed panel behind the buttons.",
        getValue = function() return Look("background") end, setValue = function(v) SetLook("background", v) end }, nil)

    _, h = W:SectionHeader(parent, "NUMBERS", y)
    y = y - h
    Row(LookSlider("Number Size", "countSize", 6, 24, 1, "The target (top left) and the count you have (bottom right)."),
        LookDropdown("Number Outline", "countOutline", ns.OUTLINES, ns.OUTLINE_ORDER))
    Row({ type = "colorpicker", text = "Target Color", tooltip = "The count you have stays red when short and green when stocked.",
        getValue = function()
            local c = Look("countColor")
            return c.r, c.g, c.b, 1
        end,
        setValue = function(r, g, b) SetLook("countColor", { r = r, g = g, b = b }) end }, nil)

    _, h = W:SectionHeader(parent, "EFFECTS", y)
    y = y - h
    local noSplash = function() return not Look("splash") end
    Row({ type = "toggle", text = "Crafting Effects", tooltip = "Bubbles rise from a poison's button when its craft starts, and droplets burst for each poison made.",
        getValue = function() return Look("splash") end,
        setValue = function(v)
            SetLook("splash", v)
            EUI:RefreshPage()
        end },
        { type = "colorpicker", text = "Effects Color", hasAlpha = true, tooltip = "Alpha 0 turns it off.",
          disabled = noSplash, disabledTooltip = "Crafting Effects",
          getValue = function()
              local c = Look("splashColor")
              return c.r, c.g, c.b, c.a or 1
          end,
          setValue = function(r, g, b, a) SetLook("splashColor", { r = r, g = g, b = b, a = a or 1 }) end })
    -- Poisons are crafted and Flash Powder is bought, so each gets its own section.
    _, h = W:SectionHeader(parent, "POISON TARGETS", y)
    y = y - h
    local poisons = {}
    for _, name in ipairs(TYPES) do
        if name ~= FLASH and Known(name) then poisons[#poisons + 1] = name end
    end
    for i = 1, #poisons, 2 do
        _, h = W:DualRow(parent, y, Slider(poisons[i]), poisons[i + 1] and Slider(poisons[i + 1]) or nil)
        y = y - h
    end
    _, h = W:SectionHeader(parent, "REAGENT TARGETS", y)
    y = y - h
    _, h = W:DualRow(parent, y, Slider(FLASH), nil)
    y = y - h
    return math.abs(y)
end

-- Clears the targets and the moved position; General's reset leaves Restock alone.
local function Reset()
    wipe(R)
    R.targets = {}
    if editor then editor.Refresh() end
    if bar then
        PlaceBar()
        UpdateBar()
    end
end

-- Re-lays a shown bar after the eUI look changed (its counts use the eUI font).
function ns.RestockLayout()
    if bar and bar:IsShown() then LayoutBar() end
end

ns.RestockModule = {
    key = "Restock", title = "Restock", onReset = Reset,
    description = "At a poison vendor, buttons beside the merchant window refill each poison to its target: click to buy the reagents and craft your best rank. Mouse wheel over a button changes its target.",
    pages = { "Restock" },
    buildPage = BuildPage,
    onPageCacheRestore = function() if editor then editor.Refresh() end end,
}
