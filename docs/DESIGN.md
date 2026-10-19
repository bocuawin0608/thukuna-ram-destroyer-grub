# INFERNAL — Art Direction & Type C Ritual Console Architecture

## 1. Sacred Artwork & Narrative Preservation

The primary visual foundation of **INFERNAL** is the supplied artwork (`image-clean.png`, referenced in `devil-jenkins.png` Panel C), which depicts the summoning of the **Jenkins Devil** above a cursed shrine as a ritual participant snaps two sticks of DDR RAM atop an island of skulls and dark debris in a blood-red ocean.

### Image Integrity Verification Record

Before designing any UI geometry, `image-clean.png` (`1024 × 576`, `16:9` aspect ratio, `1.7778`) was analyzed via [`scripts/generate-assets.py`](../scripts/generate-assets.py):

| Visual Element | Horizontal Span (`x`) | Vertical Span (`y`) | Design Policy |
| :--- | :--- | :--- | :--- |
| **Jenkins Devil (Horns, Face, Bowtie, Flame Halo)** | `36% – 63%` | `1% – 41%` | **100% Unmodified & Unobstructed** |
| **Shrine Roof & Teal-Green Inner Glow** | `39% – 60%` | `29% – 40%` | **100% Unmodified & Unobstructed** |
| **RAM-Sacrificing Summoner (Breaking 2 RAM Sticks)** | `45% – 55%` | `42% – 54%` | **100% Unmodified & Unobstructed** |
| **Central Skull & Debris Island** | `30% – 71%` | `45% – 62%` | **100% Unmodified & Unobstructed** |
| **Burning Crimson Sky** | `0% – 100%` | `0% – 56%` | Preserved; only outer-edge corner vignette |
| **Reflective Blood-Red Ocean (Foreground)** | `0% – 100%` | `56% – 100%` | Lower-water region (`y >= 63%`) hosts Type C Console |

### Permitted vs. Forbidden Image Processing

- The untouched source image is preserved in the repository root as [`image-clean.png`](../image-clean.png) and bundled inside the theme at [`theme/backgrounds/original.png`](../theme/backgrounds/original.png).
- The default `1920×1080` background ([`theme/backgrounds/infernal.png`](../theme/backgrounds/infernal.png)) applies **zero pixel modifications above `y = 62%`**, adding only a smooth localized darkening gradient in the lower foreground water (`y = 63%..98%`) so menu entries remain crisp without requiring a heavy opaque bounding box.

![Original vs Derived Background Comparison](previews/comparison_original_vs_derived.png)

---

## 2. Type C Format — Lower-Water Ornate Ritual Console

Following the reference mockup (`devil-jenkins.png`, **Panel C**), the UI is placed entirely in the foreground water (`y = 64%..90%`), completely below the central island (`y <= 62%`).

```text
┌────────────────────────────────────────────────────────────────────────────┐
│                                                                            │
│                            [ JENKINS DEVIL ]                               │
│                        [ TEAL-LIT SHRINE ROOF ]                            │
│                     [ SUMMONER BREAKING DDR RAM ]                          │
│                  [ CENTRAL SKULL & DEBRIS ISLAND ]                         │
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ y = 62% Focal Boundary ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│                              I N F E R N A L                               │
│                          ────────── ✦ ──────────                           │
│           ──◁◆⟪═══════════════════════════════════════════⟫◆▷──            │
│               ║ ◈  EndeavourOS Linux (6.18.2-arch2-1)   ◇ ║  ← ACTIVE (C) │
│           ────⟪═══════════════════════════════════════════⟫────            │
│                 ⊞  Windows Boot Manager (on /dev/nvme0n1p1)                │
│                 △  Arch Linux                                              │
│                 ⚙  Advanced options for EndeavourOS Linux                  │
│                 ▣  UEFI Firmware Settings                                  │
│                          ────────── ✦ ──────────                           │
│         [ ↑ ↓ ] Select     [ Enter ] Boot     [ e ] Edit     [ c ] Console │
└────────────────────────────────────────────────────────────────────────────┘
```

### Real GRUB `gfxmenu` Engineering vs. Static Mockup

In GNU GRUB's `gfxmenu` engine (`grub-core/gfxmenu/gui_list.c`), the `+ boot_menu` component renders dynamic boot entries as a **single vertical list** with 9-slice pixmap styling (`selected_item_pixmap_style`, `item_pixmap_style`, `menu_pixmap_style`) and a vertical scrollbar. GRUB does not have a CSS flexbox/grid engine to lay out unselected entries horizontally in 4 columns beneath a single top row.

To implement the **Type C format** faithfully within real GRUB 2.x capabilities:
1. **Unobstructed Lower-Water Placement (`top = 65%`, `left = 23%`, `width = 54%`, `height = 24%`)**: The entire boot menu sits in the dark reflective ocean below the skull island (`y > 62%`), matching Panel C's exact screen zone.
2. **Standalone Ornate Active Banner (`assets/selection/select_*.png`)**:
   - The active entry is framed in a bevelled dark-crimson & antique-gold double border (`#1c0507` fill, `#eab066` outer gold line, `#c02a20` inner crimson line).
   - `select_w.png` and `select_e.png` carry **76px lateral flame-and-filigree wing flourishes** with diamond root gems and ember needles extending outward on both sides of the active row.
   - A **bronze diamond sigil (`◇`)** is embedded on the right inside the active bar so the selected entry is unmistakable even on monochrome displays or for users with color-vision deficiency.
3. **Frameless Lower-Water Secondary Entries (`assets/borders/menu_*.png` & `assets/item/item_*.png`)**:
   - Unlike Panel A's tall opaque box, Type C leaves `menu_*.png` transparent so unselected entries sit directly over the darkened water reflections with subtle crimson-bronze underline hairlines and terminal ticks.

![Type C Preview](previews/preview_type_c.png)

![Component States and Long Menu Verification](previews/preview_states_and_long_menu.png)

---

## 3. Palette & Typography Specification

| Role | Color Name | Hex Code | Usage |
| :--- | :--- | :--- | :--- |
| **Canvas Fallback** | Abyssal Charcoal | `#0a0203` | `desktop-color` fallback |
| **Active Banner Fill** | Ritual Obsidian Crimson | `#1c0507` / `#140406` | `select_c.png` double-frame interior |
| **Primary Border** | Antique Gold / Bronze | `#eab066` / `#d4a66a` | Outer bevelled frame, filigree spear spines, compass stars |
| **Secondary Glow** | Infernal Crimson | `#dc261a` / `#b92018` | Outer banner aura, flame wings, timeout bar highlight |
| **Shrine Accent** | Cursed Jade Teal | `#46d29b` | Preserved in shrine roof artwork |
| **Active Entry Text** | Luminous Parchment Ivory | `#faeedc` | `selected_item_color` (`DejaVu Serif Bold 18`) |
| **Inactive Entry Text** | Muted Warm Ivory | `#e0ceb8` | `item_color` (`DejaVu Serif Regular 16`) |

### Bundled GRUB `.pf2` Bitmap Fonts

Generated via `grub-mkfont` in [`theme/fonts/`](../theme/fonts/) with full Unicode coverage for navigation arrows (`↑`, `↓`) and geometric markers:
- `infernal_serif_regular_16.pf2` (`DejaVu Serif Regular 16`)
- `infernal_serif_bold_18.pf2` (`DejaVu Serif Bold 18`)
- `infernal_serif_bold_20.pf2` (`DejaVu Serif Bold 20`)
- `infernal_mono_14.pf2` (`DejaVu Sans Mono Regular 14` — terminal & console fallback)

---

## 4. Background Variants & Asset Replacement Workflow

The repository ships pre-generated resolution variants in [`theme/backgrounds/`](../theme/backgrounds/):
- `infernal.png` — `1920×1080` (`16:9` Full HD default)
- `infernal-2560x1440.png` — `2560×1440` (`16:9` QHD / 2K)
- `infernal-1920x1200.png` — `1920×1200` (`16:10` WUXGA, aspect-preserving sky/water extension)
- `infernal-1024x768.png` — `1024×768` (`4:3` legacy firmware/VBE framebuffer)
- `original.png` — `1024×576` untouched copy of `image-clean.png`
- `fallback.png` — `1280×720` lightweight (`3.9 KiB`) procedural dark-crimson fallback

To install with a specific resolution or custom PNG background without overwriting source files:
```bash
sudo ./install.sh --install --resolution 2560x1440
# or use the untouched original image:
sudo ./install.sh --install --resolution original
# or supply a custom PNG background:
sudo ./install.sh --install --background /path/to/custom.png
```

