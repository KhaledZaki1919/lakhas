# لخّص (Lakhas) — Design System: طحينة ونعناع · Tahini & Mint

Status: **Final (ADR-017)** · Locked 2026-10-11

Warm, food-forward and homey: it should feel like a kitchen, not a gym. Every screen is built from these tokens. In code they live in `LakhasKit/Sources/LakhasKit/Theme/` as asset-catalog colors (light/dark variants) plus Swift constants. Views never use literal colors, sizes or radii.

Directions B (Night Market) and C (Hibiscus Ledger) were considered and set aside. The comparison stays in `design-preview.html`.

---

## 1. Color tokens

All text pairs meet **WCAG AA ≥ 4.5:1** on their background; graphic marks meet **≥ 3:1**. The ratios were measured on 2026-10-11.

### 1.1 Core
| Token | Light | Dark | Use | Contrast |
|---|---|---|---|---|
| `bg` | `#FBF7F0` | `#171412` | screen background | — |
| `surface` | `#FFFFFF` | `#221E1B` | cards, sheets, tab bar | — |
| `surfaceSunken` | `#F4EEE4` | `#1D1A17` | input fields, grouped rows | — |
| `ink` | `#2A2420` | `#F3EDE4` | primary text | 14.3 / 15.8 on bg |
| `muted` | `#6B6158` | `#A89E93` | secondary text, captions | 5.7 / 7.0 on bg; 6.0 / 6.3 on surface |
| `line` | `#E6DCCC` | `#332D28` | hairlines, dividers, dashed "add" rows | decorative |
| `track` | `#EFE7DA` | `#3A332D` | ring and bar tracks | decorative |

### 1.2 Brand & semantic
| Token | Light | Dark | Use | Contrast |
|---|---|---|---|---|
| `primary` (mint) | `#1F7A5A` | `#5CC59B` | primary buttons, ring fill, active tab, links | 4.9 / 8.7 on bg; 7.8 dark on surface |
| `onPrimary` | `#FFFFFF` | `#0E1F18` | text/icons on `primary` | 5.3 / 8.1 |
| `halo` (tahini) | `#EAD9BA` | `#4A3F30` | halo around "+", selection tints | decorative |
| `accent` (pomegranate) | `#B4363F` | `#F07A80` | over target, destructive actions, errors | 5.6 / 6.8 on bg; 5.9 / 6.1 on surface |
| `success` | `#1F7A5A` | `#5CC59B` | target reached, saved (same as primary) | as primary |
| `warning` | `#9A6200` | `#F0B54A` | low confidence, floor note, cap almost used | 4.8 / 10.0 on bg |

### 1.3 Macros (always paired with a label and a glyph, never color alone)
| Token | Light | Dark | Glyph | Contrast vs surface |
|---|---|---|---|---|
| `protein` | `#2F6FB0` | `#6FA8E6` | egg | 5.2 / 6.6 |
| `carbs` | `#A86F0E` | `#E7B44F` | wheat stalk | 4.3 / 8.7 |
| `fat` | `#8A5BB8` | `#B993E3` | drop | 4.9 / 6.6 |

### 1.4 Placeholder plates (no AI images, ADR-020 / ADR-026)
A dish, meal or recipe without the user's photo shows its category symbol on a plate: `surface` disc, `halo` rim, a well tinted at 16% and the symbol in the tint. The tints come from the old illustration palette:

| Token | Light | Dark | Categories |
|---|---|---|---|
| `primary` (mint) | `#1F7A5A` | `#5CC59B` | fish, salad, drinks |
| `accent` (pomegranate) | `#B4363F` | `#F07A80` | stews, grills, pasta |
| `plateOlive` | `#6B7A3A` | `#A9B86E` | beans, fruit |
| `plateWheat` | `#8F6410` | `#E3B65A` | eggs, bread, soups |
| `plateTahini` | `#7E6236` | `#D9BF8F` | dairy, rice dishes |
| `plateEggplant` | `#4B2E4F` | `#C79BCB` | sweets, snacks |

Plates are decorative (hidden from VoiceOver); the dish name always sits next to them.

---

## 2. Typography

System fonts only: **SF Arabic** and **SF Pro**, picked automatically per language. Every style is a Dynamic Type text style, so it scales.

| Token | Text style | Default size | Weight | Use |
|---|---|---|---|---|
| `display` | `.largeTitle` | 34 | Bold, monospaced digits | remaining calories |
| `title1` | `.title` | 28 | Bold | screen titles |
| `title2` | `.title2` | 22 | Semibold | section headers, "Today" |
| `headline` | `.headline` | 17 | Semibold | card titles, meal names |
| `body` | `.body` | 17 | Regular | content |
| `callout` | `.callout` | 16 | Regular | secondary content |
| `footnote` | `.footnote` | 13 | Regular | macro labels, group headers |
| `caption` | `.caption` | 12 | Medium | chips, tab labels, units |

- **Numbers:** `.monospacedDigit()` everywhere they change. Digit style (Western / Eastern Arabic) comes from the number formatter, not the font.
- **Arabic:** +2pt line spacing at `body` and below.
- **Latin wordmark:** SF Pro Rounded Bold.

---

## 3. Spacing, shape, elevation

| Token | Value |
|---|---|
| `space` scale | 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 |
| Screen side margin | 16 |
| `radius.card` | 20 |
| `radius.control` | 14 (inputs, segmented controls) |
| `radius.chip` | full (capsule) |
| Buttons | capsule, min height 50, primary fill |
| Min hit target | 44 × 44 |
| `shadow.card` (light only) | `0 1 2 ink@6%` + `0 6 16 ink@7%` |
| Dark mode elevation | no shadows; `surface` is lighter than `bg` |

---

## 4. Components

| Component | Spec |
|---|---|
| **Calorie ring** | 148pt; 14pt stroke; `track` + `primary`, round cap; fills **clockwise in both languages**. Center: remaining (`display`), "kcal left" (`caption`, muted), "eaten / target" (`caption`, muted). Over target: the fill turns `accent` and the label reads "over by N". VoiceOver: "1,179 of 2,100 calories, 921 left". |
| **Macro bars** | Card on `surface`. Each row: glyph + name (`footnote` semibold), "eaten / target g" (`footnote`, muted, trailing), 8pt bar filling from the leading edge. |
| **Date strip** | 7 days, oldest → newest in reading direction. Today = `primary` pill with `onPrimary` text. Days with logs get a 4pt `primary` dot. |
| **Today header** | App mark (30pt) + "Today" (`title2`) + date (`footnote`, muted). The trailing **Progress** button (chart icon, labeled "Progress" for VoiceOver) replaces the old Progress tab. |
| **Meal group** | Header row: meal name (`footnote` semibold) + group kcal (`footnote`, muted). Then meal cards. An empty group shows a dashed `line` row "+ Add dinner" in `primary`. |
| **Meal card** | `surface`, `radius.card`, `shadow.card`. Leading 44pt circular "plate" photo/illustration, title (`headline`, 1 line, truncates), subtitle "450 g · from photo" (`caption`, muted), trailing kcal (`headline` + `caption` unit). An optional macro row shows three mini columns with 3pt bars. Swipe actions: re-log (`primary`), delete (`accent`) with Undo toast. |
| **Tab bar** | `surface` with a top hairline. Order: **Today, Recipes, [+], Explore, Workouts**. Active = `primary` + semibold label. |
| **"+" button** | 54pt mint circle, `onPrimary` plus icon, 5pt `halo` ring, raised 22pt above the bar. Opens a sheet: Photo · Text · Barcode · Saved meal. |
| **Review list (AI result)** | Rows: name, grams (tap to type; a slider below on expand), kcal. Low-confidence items get a `warning` dot + "check the amount". A sticky footer shows totals + the meal-type picker + Save. |
| **Water fill column** | Rounded glass, `primary` water at 85% opacity with a gentle wave while dragging; snaps to 50 ml (under 500) / 100 ml; haptic tick per step. |
| **Skeletons** | `surfaceSunken` blocks with a slow shimmer (none under Reduce Motion). |
| **Toasts / errors** | `ink` capsule on light, `surface` on dark. Errors are specific with a Retry action: "Couldn't reach the server. Check your connection and try again." |

---

## 5. Motion

- **Springs:** response 0.35, damping 0.8 for presses and sheet changes. Number changes roll.
- **Celebration** (target reached): sesame-dot confetti in the macro colors, about 1.2s. Under Reduce Motion it's a cross-fade with a checkmark.
- **Haptics:** success on log, light tick on slider and water steps, warning on cap reached.

---

## 6. Iconography & logo

- **Icons:** SF Symbols, regular weight, mirrored automatically in RTL where directional.
- **Logo mark:** the **shadda (ّ)** of لخّص drawn as three fork tines over a circular plate.
  - **App icon:** a mint field, a tahini plate ring, and white tines. The mark stays legible at 29pt; it was checked in the preview.
- **Arabic wordmark:** لخّص in SF Arabic Bold, with a hand-drawn shadda in `primary`.
- **Latin wordmark:** "Lakhas" in SF Pro Rounded Bold.
- Vector sources will live in `/docs/brand/` (Phase 1: SVG mark + icon set export).

---

## 7. Bidi & accessibility rules

- Use leading/trailing only. Time axes run oldest → newest in reading direction; the ring is always clockwise.
- Every control has a VoiceOver label and value; macros are announced as "Protein, 52 of 140 grams".
- Dynamic Type up to AX5: layouts switch to vertical stacks at accessibility sizes.
- Test every screen in Arabic + English × light + dark × default + AX3 text size.
