# TruFocus brand handover

Version 2.0 · Ember Open · October 2026 · Owner: Jason Koh

New-world focus for ADHD brains.

This version replaces every earlier handover (v1.0 classic, v1.1 lowercase). Discard those files.

## 1. The idea

One ring, one point of light. The ring is everything you are keeping out; the core is the one task you are in. The core glows because that is what focus feels like when it lands: warm, bright, and impossible to miss.

The rules that carry the system:

1. **Solid shapes, luminous light.** The ring and core are always clean, solid forms. Depth comes from the gradient and the soft glow, never from texture or clusters of dots.
2. **One accent.** Signal orange and its gradient. No second colour.
3. **Glow on dark, flat on light.** A glow on a light background goes muddy, so light surfaces use the flat symbol.
4. **Small sizes go solid.** Below 24 px (and app icons below 40 px), use the small cut: thicker ring, no glow, no gradient.

## 2. Folder

| Folder | Contents | Use for |
| --- | --- | --- |
| `01-symbol` | `ember-glow` (dark backgrounds), `ember-flat` (light backgrounds), `mono-black`, `mono-white`, and `small-*` cuts for below 24 px. SVG + PNG at 1024 | Anywhere the mark appears alone |
| `02-wordmark` | "TruFocus" in Geist SemiBold, outlined. Paper, Ink, black, white | Rare. Prefer the lockup |
| `03-lockup` | Symbol + wordmark: `dark` (with glow), `light` (flat), `mono-black`, `mono-white`. SVG + PNG 2400 px | The main logo: website header, decks, documents, social |
| `04-app-icon/ios` | `AppIcon-1024` (default), `Dark`, `Tinted`, `Alt-Paper` | Xcode asset catalogue |
| `04-app-icon/macos` | 1024 on Apple's 824 px tile with shadow, plus 16 to 512 px | Mac `.icns` |
| `05-web` | `favicon.svg` (adapts to dark mode), `favicon.ico`, PNG favicons, `apple-touch-icon`, PWA icons, `og-image.png` | Website head |
| `06-menu-bar` | `MenuBarIconTemplate` 18 px and @2x, black on transparent | Mac menu bar |
| `07-motion` | `trufocus-particle-motion.html`: particles scatter, then gather into the ring and core | Website hero, launch animation, the "Done" moment |
| `tokens.json`, `tokens.css` | Colour, gradients and geometry | Engineering |

## 3. Colour

| Token | Value | Role |
| --- | --- | --- |
| Signal | `#FF5A1F` | Brand orange. Ring base, core edge, glow |
| Core gradient | `#FFE6D6` → `#FF9560` (45%) → `#FF5A1F` | The core, centred radial |
| Ring gradient | `#FF7A40` top → `#E2460E` bottom | The ring, vertical |
| Ink | `#050506` | Dark backgrounds, text on light |
| Paper | `#F4F3EE` | Light backgrounds, text on dark |

## 4. Symbol geometry

Drawn on a 100 x 100 field, centred.

| Part | Standard | Small (below 24 px) |
| --- | --- | --- |
| Ring | radius 37, stroke 5.5, ring gradient | radius 37, stroke 9, solid |
| Core | radius 17, core gradient | radius 18, solid |
| Core glow | radius 22.1, Signal, 65% opacity, blur 6 | none |
| Ring glow | stroke 5.5, Signal, 30% opacity, blur 3.2 | none |

- The glow sits inside the 100 x 100 field, so the files can be placed edge to edge without clipping.
- Clear space: the core's diameter (34 units) on every side.
- Minimum size: 16 px (small cut).

## 5. Lockup

- Wordmark: "TruFocus", Geist SemiBold, tracking -0.038em, outlined in the files.
- The symbol's field is 1.27 x the font size, centred on the cap height. The gap is 0.22 x the font size.
- Use `lockup-dark` on Ink or photography with a dark field. Use `lockup-light` on Paper or white.
- Minimum lockup width: 120 px. Below that, use the symbol alone.

## 6. App icons

The tile is a dark glass surface: a soft top-left highlight (`#28282C` → `#060607`) with a faint warm vignette behind the symbol. The symbol is 62% of the tile.

**iOS (Xcode 16+).** In `Assets.xcassets/AppIcon`, single size 1024: Any `AppIcon-1024.png`, Dark `AppIcon-Dark-1024.png`, Tinted `AppIcon-Tinted-1024.png`. Files are square and full-bleed; iOS applies the mask. Ship `AppIcon-Alt-Paper` as an alternate icon via `setAlternateIconName`.

**macOS.** Build the `.icns` from `04-app-icon/macos` with `iconutil`, or drop the 1024 into the asset catalogue. The tile and shadow are already in the artwork.

**Menu bar.** Add `MenuBarIconTemplate.png` and `@2x`, set Render As: Template Image. macOS colours it for light and dark menu bars.

## 7. Web

```html
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<meta property="og:image" content="https://trufocus.app/og-image.png">
<meta name="theme-color" content="#050506">
```

Website hero: embed `07-motion/trufocus-particle-motion.html` (or port its script). It respects `prefers-reduced-motion` and shows the gathered mark without animation.

Live UI (CSS) version of the core:

```css
.tf-core { width: 34px; height: 34px; border-radius: 50%;
  background: radial-gradient(circle, #FFE6D6 0%, #FF9560 45%, #FF5A1F 100%);
  box-shadow: 0 0 18px rgba(255, 90, 31, 0.55); }
```

## 8. Do not

- Replace the solid core with dots, particles or texture. Clusters of small dots read as unsettling up close.
- Use the glow on light backgrounds.
- Use the gradient or glow below 24 px.
- Add a second accent colour, outlines, bevels or gloss.
- Offset, stretch or resize the core relative to the ring.
- Retype the wordmark in a live font. Use the outlined files.

## 9. Licences

Geist: SIL Open Font Licence 1.1. All artwork made for TruFocus and owned by the business.

## 10. Before launch

- Trademark search on the name and the ring-and-core device (Class 9 and 42).
- Check the app icon on a real phone in light, dark and tinted modes, at home-screen size and in Settings (29 pt).
- Note: a small habit app called "True Focus" is on the App Store. Reserve "TruFocus" in App Store Connect early.
