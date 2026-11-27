## Update 1.3.3 `WEB`
#### Changes
- Generated Web favicon and PWA icons (`192px`, `512px`, and maskable variants) from the Android monochrome adaptive icon on `#009688`.
- Updated `web/manifest.json` with app title, description, `#009688` theme color, and `#0A0E14` background color.

## Update 1.3.2 `FIX`
#### Fixes
- Wired Pattern Explorer to `engine.allPatterns` (`catalogPatterns` + `customPatterns`) so all 42 LifeWiki patterns—including **Puffers & Mega**, discoverer attributions, and LifeWiki links—appear instead of the 21-pattern fallback.
- Made framed viewport outer margins symmetric (`12dp` on all sides) and added a subtle `outlineVariant` frame border for crisp edges on dark desktop/web displays.

## Update 1.3.1 `RELEASE`
#### Changes
- Added explicit LifeWiki (`conwaylife.com`) & pattern discoverer attribution with a direct **Visit conwaylife.com** CTA in the Pattern Library and About / Credits.
- Linked the `conwaylife.com` hub across the app and README for exploring additional Game of Life patterns.
#### Miscellaneous
- Prepared `1.3.1+26112704` release metadata for Google Play Store and GitHub Releases.

## Update 1.3.0 `EXPLORER`
#### Changes
- Added the LifeWiki Pattern Explorer with 30+ curated patterns (`assets/patterns/catalog.json`) including heavy stress-test guns and puffers.
- Added instant search filtering by pattern name, author, and description, plus a new Puffers category chip in the Pattern Library.
- Added pattern author attribution, one-tap **Load Centered** placement, and direct **LifeWiki** external links in the Pattern Library.

## Update 1.2.1 `SHARE`
#### Changes
- Added QR code & `gol.puzzak.page` deep-link pattern sharing (`lib/widgets/share_sheet.dart`) with editable pattern names, compact binary URL encoding, RLE copy, and one-tap saving to custom patterns.
- Upgraded the Pattern Library share button to open the QR & link Share Sheet for every built-in and custom pattern.
- Added incoming deep-link and web URL (`https://gol.puzzak.page/v?d=...` / `gol://v?d=...`) parsing on startup and live intents, with a dismissible floating preview pill on the canvas.
- Added automated GitHub Pages Flutter Web deployment (`gol.puzzak.page`).

## Update 1.2.0 `M3X`
#### Changes
- Rebuilt the simulation core with a dual-backend `GolGrid` supporting Infinite (sparse 16×16 chunked), Toroidal (wrapping), and Bounded (edge-clipped) topologies.
- Added outer-totalistic `B/S` rule engine with built-in presets (Conway `B3/S23`, HighLife `B36/S23`, Day & Night, Seeds, Life Without Death, Maze, Anneal) and custom rule parsing.
- Added focal-point pinch-to-zoom camera, two-finger panning, fit-to-content, and dedicated Draw, Pan, Stamp (rotate/flip), and Crop-to-RLE canvas tools.
- Added curated Wikipedia Pattern Library (still lifes, oscillators, spaceships, methuselahs, and glider guns) with full Conway RLE / `.cells` codec and persistent custom pattern storage.
- Added 30-step undo/redo snapshot history and speed control from 1 to 120 TPS.
- Migrated the entire UI to Material 3 Expressive (`m3x`) with a 3-state adaptive layout (compact phone, medium tablet, expanded desktop), 7 color palettes with cell-age shading, and accessible ≥ 48 dp touch targets.
- Added English and Ukrainian localization powered by `m3x_dict`.
#### Fixes
- Eliminated grid-resize resets when rotating the device or resizing desktop windows.
- Fixed negative-coordinate chunk addressing and cross-boundary neighbor accumulation in infinite mode.
#### Miscellaneous
- Upgraded Flutter SDK constraints, Android build configuration, and added comprehensive engine and widget test suites.

## Update 1.1.3 `POLISH`
#### Changes
- Improved dynamic Material You color detection on Android 12+ and ChromeOS.
- Added live frame-time and FPS diagnostics card in the settings sheet.
#### Fixes
- Fixed edge-to-edge system bar styling across older and newer Android SDK levels.

## Update 1.1.1 `INIT`
#### Changes
- Initial public release of Golr (Conway's Game of Life) on Google Play and GitHub.
- Implemented interactive touch/mouse cell drawing, customizable cell corner radius, border thickness, scale, speed controls, and custom color picker.

---
> Template for later updates
```Markdown
## Update 1.0.0 `TAG`
#### Changes
#### Fixes
#### Known Issues
#### Miscellaneous
```
