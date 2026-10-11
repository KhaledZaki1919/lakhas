# لخّص (Lakhas) — Visual Directions

Status: **Awaiting your choice (Phase 0)** · Last updated: 2026-10-11

Three original directions follow. Every direction shares the same rules below. Only the palette, shapes, motion and personality differ. Pick one (or mix: "B's palette with A's shapes"), and I'll turn it into `Theme` tokens in `LakhasKit` during Phase 1.

---

## Shared foundations (all directions)

### Typography
- **System fonts only**: SF Arabic for Arabic and SF Pro for Latin, chosen automatically by the system for the active language. No license risk, full Dynamic Type, and good Arabic shaping and diacritics (the shadda in لخّص renders correctly).
- **Numbers:** SF Pro numerals with `.monospacedDigit()` so counters don't jitter. Eastern Arabic digits (٠–٩) come from a formatter when the setting is on, not from a font change.
- **Type scale** maps to Dynamic Type text styles, so everything scales:

| Token | Text style | Default size | Weight | Use |
|---|---|---|---|---|
| `display` | `.largeTitle` | 34 | Bold | remaining calories number |
| `title1` | `.title` | 28 | Bold | screen titles |
| `title2` | `.title2` | 22 | Semibold | section headers |
| `headline` | `.headline` | 17 | Semibold | card titles, meal names |
| `body` | `.body` | 17 | Regular | content |
| `callout` | `.callout` | 16 | Regular | secondary content |
| `footnote` | `.footnote` | 13 | Regular | macro labels, captions |
| `caption` | `.caption` | 12 | Medium | chips, badges |

Arabic text gets +2pt line spacing at `body` and below. Arabic script needs more vertical room than Latin at the same point size.

### Layout & bidi rules
- Use leading/trailing everywhere. Directional icons (chevrons, back, "next") use SF Symbols that mirror automatically.
- Time axes (weekly bars, weight chart, date strip) run oldest → newest *in reading direction*, so they flip in Arabic. The calorie ring always fills clockwise in both languages, the way a clock face doesn't mirror.
- 8-pt spacing grid; card corner radius per direction; minimum hit target 44×44.
- Macros are always **name + number + bar**, never color alone. Protein / Carbs / Fat each also get a distinct SF Symbol glyph so colorblind users have three cues.

### Accessibility
- All text/background pairs listed below were checked at **≥ 4.5:1** (WCAG AA). Ratios are in each table.
- Every interactive element gets a VoiceOver label and value (e.g. the ring reads "1,240 of 2,100 calories, 860 remaining").
- Reduce Motion replaces celebration and fill animations with a cross-fade.

### Logo concept (common seed, styled per direction)
لخّص means "summarize". The mark is built from the word's own **shadda (ّ)**: its three-stroke "w" shape doubles as fork tines / a small crown. It sits over a circular "plate" form, so the logo reads as *a plate, summarized*.
- **App icon:** the shadda-on-plate mark alone, no letters (it must read at 29pt).
- **Arabic wordmark:** لخّص, with a custom-drawn shadda in the accent color; the remaining letters are set in SF Arabic Bold and then outlined/adjusted by hand.
- **Latin wordmark:** "Lakhas" in SF Pro Rounded/Display Bold, with a small three-stroke mark floating above the "kh" to tie it to the Arabic.

The final vector logo comes after you pick a direction. I'll produce SVG sources in `/docs/brand/` and an icon set from them.

---

## Direction A — **طحينة ونعناع · Tahini & Mint**
*Warm, food-forward, homey. Feels like a kitchen, not a gym.*

**Personality:** Friendly and reassuring. Best for a mainstream audience that wants to "eat better" more than "hit macros".

| Token | Light | Dark | Contrast (on bg) |
|---|---|---|---|
| `bg` | `#FBF7F0` warm cream | `#171412` roasted brown-black | — |
| `surface` (cards) | `#FFFFFF` | `#221E1B` | — |
| `ink` (primary text) | `#2A2420` | `#F3EDE4` | 14.3 / 15.8 |
| `muted` (secondary text) | `#6B6158` | `#A89E93` | 5.7 / 7.0 |
| `primary` (mint) | `#1F7A5A` | `#5CC59B` | 4.9 / 8.7 |
| `onPrimary` | `#FFFFFF` | `#0E1F18` | 5.3 / — |
| `accent` (pomegranate: over-target, delete) | `#B4363F` | `#F07A80` | 5.6 / 6.8 |
| `protein` / `carbs` / `fat` | `#2F6FB0` / `#C98A1B` / `#8A5BB8` | `#6FA8E6` / `#E7B44F` / `#B993E3` | (bars, always labeled) |

**Shapes:** Large radius (20pt cards, fully round buttons), soft shadows in light mode and no shadows in dark mode.
**Signature components:**
- *Today ring:* thick ring with a cream track; the remaining number sits in the center in `display`.
- *Meal cards:* a photo thumbnail is a circle "plate" with a subtle rim.
- *Water fill column:* a rounded glass with a gentle wave surface while dragging.
- *Center "+":* a mint circle with a tahini-colored halo.

**Motion:** Springy and soft. The celebration is falling sesame/confetti dots in the macro colors.
**Illustration palette for AI SVGs:** cream, tahini, mint, pomegranate, olive, eggplant, and wheat (7 fixed colors).

---

## Direction B — **سوق الليل · Night Market**
*Dark-first, high-energy, saffron lights on deep indigo. Feels like a modern fitness tool with Arab warmth.*

**Personality:** Confident and motivating. Best if the gym/workout side is a big part of the identity.

| Token | Light | Dark (hero) | Contrast (on bg) |
|---|---|---|---|
| `bg` | `#F6F5F2` | `#12141F` deep indigo | — |
| `surface` | `#FFFFFF` | `#1C1F2E` | — |
| `ink` | `#151826` | `#F5F3EE` | 16.2 / 16.5 |
| `muted` | `#5B6075` | `#9AA0B8` | 5.7 / 7.1 |
| `primary` (saffron) | `#9A5B00` | `#F4B23E` | 5.0 / 9.9 |
| `onPrimary` | `#FFFFFF` | `#1A1408` | — / 9.8 |
| `secondary` (teal) | `#00756B` | `#3FD0C0` | 5.1 / 9.6 |
| `accent` (over-target) | `#B3261E` | `#FF7A6E` | (verified at build) |
| `protein` / `carbs` / `fat` | `#00756B` / `#9A5B00` / `#7A4FD0` | `#3FD0C0` / `#F4B23E` / `#A98BFF` | (labeled) |

**Shapes:** Medium radius (14pt) and tighter spacing. Thin 1pt hairline borders instead of shadows. Numbers are large and bold.
**Signature components:**
- *Today ring:* a segmented ring (each segment = one logged meal) with a saffron glow at the tip.
- *Date strip:* a glowing "lantern" dot under today's date.
- *Workout logging:* oversized set rows with one-tap "repeat last set".
- *Water column:* a tall neon-edged tube.
- *Center "+":* a saffron hexagon (a nod to geometric Islamic patterns, simplified).

**Motion:** Snappy (short durations, slight overshoot). The celebration is a radial burst of light from the ring.
**Default appearance:** Follows the system setting like the others, but marketing and screenshots lead with dark.

---

## Direction C — **كركديه · Hibiscus Ledger**
*Calm, editorial, numbers-first. Clean white space with a single deep hibiscus accent.*

**Personality:** Precise and trustworthy, like a well-designed notebook. Best if "accurate AI + clean data" is the main selling point.

| Token | Light | Dark | Contrast (on bg) |
|---|---|---|---|
| `bg` | `#FFFFFF` | `#0E0F12` | — |
| `surface` | `#F5F5F7` | `#1A1B20` | — |
| `ink` | `#1B1D22` | `#ECEDEF` | 16.9 / 16.4 |
| `muted` | `#5F6470` | `#9A9FAA` | 5.9 / 7.2 |
| `primary` (hibiscus) | `#A3214A` | `#F0729A` | 7.3 / 6.9 |
| `onPrimary` | `#FFFFFF` | `#2A0712` | 7.3 / — |
| `accent` (success/target hit) | `#1E7A4C` | `#5FD39A` | (verified at build) |
| `protein` / `carbs` / `fat` | grayscale ramp + glyphs; hibiscus only for "remaining" | same | (labeled) |

**Shapes:** Small radius (10pt), flat surfaces, and dividers over cards. Generous margins.
**Signature components:**
- *Today:* instead of a ring, a large "ledger" number line: `2,100 target − 1,240 eaten = 860 left`. A thin hibiscus progress rule runs underneath. (A ring is still available as a widget.)
- *Meals:* typographic rows (name, grams, kcal in tabular digits).
- *Review screen:* reads like a receipt, with a grams slider under each line.
- *Center "+":* a hibiscus circle with a hairline cross.

**Motion:** Minimal; numbers roll on change. The celebration is a single ink-stroke underline that draws itself under the total and a small hibiscus flower blooming.
**Note:** The macro "grayscale + glyph" approach is the most accessible, but the least colorful. It can be swapped for A's macro colors.

---

## My recommendation
**A (Tahini & Mint)** for the broad Arab market: warm, food-centric and clearly different from typical neon fitness apps. If you want the workout side to lead the brand, choose **B**. **C** suits a premium, accuracy-focused positioning.

Tell me the direction (and any tweaks), plus any logo preferences. Then I'll lock the tokens and draw the logo in Phase 1.
