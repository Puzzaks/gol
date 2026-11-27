<div align="center">
<h1>Golr</h1>
<h3>Conway's Game of Life — Material 3 Expressive</h3>
An interactive, high-performance cellular automaton simulator built with Flutter and <code>m3x</code>.<br><br>
<a href="https://play.google.com/store/apps/details?id=page.puzzak.gol"><img src="https://img.shields.io/badge/Google_Play-Golr-414141?style=flat-square&logo=google-play&logoColor=white" height="20" alt="Google Play"></a>
<a href="https://github.com/Puzzaks/gol/releases"><img src="https://img.shields.io/github/v/release/Puzzaks/gol?style=flat-square&label=Release" height="20" alt="GitHub Release"></a>
<img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white" height="20" alt="Flutter">
<img src="https://img.shields.io/badge/Material_3-Expressive-6750A4?style=flat-square" height="20" alt="Material 3 Expressive">
</div>

> *"The Game of Life is not your typical computer game. It is a cellular automaton, and was invented by Cambridge mathematician John Conway."* — [Wikipedia](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life)

---

### Features
 - **Infinite, Toroidal & Bounded Engine**: Dual-backend simulation supporting an unbounded sparse 16×16 chunk universe alongside double-buffered toroidal and bounded finite grids, with outer-totalistic `B/S` rule presets (Conway, HighLife, Day & Night, Seeds, Life Without Death, Maze, Anneal) and custom rule notation.
 - **Pinch-to-Zoom & Precision Canvas Tools**: Smooth focal-point pinch-to-zoom and two-finger panning paired with dedicated Draw, Pan, Stamp (with 90° rotation and horizontal flip), and Crop-to-RLE tools, plus 30-step undo/redo history.
 - **Wikipedia Pattern Library & Conway RLE**: 20+ built-in still lifes, oscillators, spaceships, methuselahs, and glider guns, full Conway RLE and plaintext `.cells` import/export, and persistent custom pattern saving.
 - **Material 3 Expressive (`m3x`) Adaptive UI**: 3-state responsive layout tailored for compact phones, medium tablets, and expanded desktop windows, featuring dynamic Material You theming, 7 curated palettes with cell-age shading, haptic feedback, and English / Ukrainian localization.

### Screenshots
![Play Store Screenshots](assets/bundle_android.jpg)

### Resources
- [Full history](CHANGELOG.md)
- [Future plans](ROADMAP.md)
- [Google Play Store](https://play.google.com/store/apps/details?id=page.puzzak.gol)
- [GitHub Releases](https://github.com/Puzzaks/gol/releases)

---

### Credits
- Built with [Flutter](https://flutter.dev/) and the `m3x` Material 3 Expressive design system.
- Assisted by [Google Antigravity](https://antigravity.google/).
- And to Armed forces of Ukraine for keeping me safe. [Stand with Ukraine](https://war.ukraine.ua/support-ukraine/)!
