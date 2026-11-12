# EllesmereUI Poisons

**Think Poisoner + Hemlock in one addon, built into EllesmereUI.** A poison dock to apply your poisons, stones and oils, and a restock bar to refill your poisons at the vendor. Each module has its own Enable toggle, so you can run both or only one.

![Preview](Media/preview.gif)

Requires **[EllesmereUI](https://www.curseforge.com/wow/addons/ellesmereui)**. Made for **WoW Forever**.

## Dock (the Poisoner part)

One movable button. Hover or click it to open a flyout of every poison, sharpening stone, weightstone and oil in your bags, with their counts.

- **Left-click** an item for your main hand, **right-click** for your off hand.
- **Right-click the button** to open its settings.
- A splash bursts from the item you used when it goes on your weapon. Bubbles rise while a poison is on, and sparkles while a stone or oil is.
- Items you have applied can glow in the flyout.
- Drag to reorder the list, and click to hide what you don't want.

## Restock (the Hemlock part)

At a poison vendor, buttons appear beside the merchant window, one for each poison you know and one for Flash Powder. Each button shows your target (top left) and what you have (bottom right, red when short, green when stocked).

- **Click** to buy the reagents, then **click again** to craft your best rank up to the target.
- Flash Powder is bought straight up to its target.
- The **mouse wheel** over a button changes its target, and **right-click** opens the settings.
- Tooltips tell you what the next click will do.

## Settings

Everything lives in the EllesmereUI options, and both the dock and the restock bar move in **Unlock Mode**.

**Dock**
- **General:** Enable, Hide When None in Bags, Highest Rank Only, Tooltips (Full, Name Only, Off), Icon Shape (Cropped, Square, Circle, Curved Square, Diamond, Hexagon, Portrait, Shield)
- **Poisons, stones and oils:** order, and which ones to show
- **Button:** Button Icon (Poisons Skill, Envenomed Blade, Dual Wield, Sharpening Stone, Last Applied, Custom), Button Size, Opacity, Show Only on Mouseover
- **Flyout:** Flyout Direction (Up, Down, Left, Right), Item Size, Spacing, Flyout Background
- **Behavior:** Open On (Hover, Click), After a Click (Stay Open, Hide After Leaving), Open Delay, Hide Delay, Close After Use
- **Animation:** Animation (Instant, Fade, Slide, Fade and Slide, Grow, Cascade), Easing (Linear, Ease Out, Ease In, Ease In Out, Overshoot), Duration, Cascade Delay
- **Highlight Applied:** on/off, color, static or pulse, pulse speed
- **Item Count:** on/off, position, size, outline, X/Y offset, color
- **Effects:** Enable Effects, Effects Only on Hover, Effects Only When Applied, Applied On (Any Weapon, Main Hand Only), Splash Opacity, Bubbles Color, Sparkles Color

**Restock**
- **Enable**
- **Buttons:** order, and which ones to show
- **Targets:** a target for each poison you have learned, plus Flash Powder
- **Layout:** Layout (vertical or horizontal), Icon Shape, Button Size, Spacing, Background
- **Numbers:** Number Size, Number Outline, Target Color
- **Effects:** Crafting Effects (bubbles while a poison crafts, droplets for each one made)

## Notes

- For timers and reminders when your poisons wear off, use the **AuraBuff Reminders** module that comes with EllesmereUI.
- Translated into German, French, Spanish, Italian, Brazilian Portuguese, Russian, Korean and Chinese (Simplified and Traditional). It follows EllesmereUI's language setting, and poison names match the game's when EllesmereUI shows your client's language.
- The flyout can't open in combat, because the game blocks it. Prepare your weapons before the pull.
- `/epoisons debug` lists what the dock sees in your bags and on each weapon, which helps with bug reports.
