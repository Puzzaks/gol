# Project Roadmap
  - [ ] Planned/ indev change
  - [x] Implemented change
  - `~version` Upstream version of this change
  - `version` Downstream version of this change

---
## Phase 1 `M3x & Infinite Engine Overhaul` 5/5
 - [x] **Dual-Backend Simulation Engine** `1.2.0`
    - Sparse 16×16 chunked infinite plane with JS/Web-safe packed keys alongside double-buffered toroidal and bounded finite grids
 - [x] **Multi-Rule & Snapshot History** `1.2.0`
    - Outer-totalistic `B/S` rule parser with 7 built-in presets and 30-step undo/redo snapshots
 - [x] **Interactive Camera & Canvas Tools** `1.2.0`
    - Focal-point pinch-to-zoom, fit-to-content, and Draw / Pan / Stamp (rotate & flip) / Crop tools
 - [x] **Wikipedia Pattern Library & RLE Codec** `1.2.0`
    - 20+ built-in patterns, standard Conway RLE & plaintext `.cells` import/export, and custom pattern persistence
 - [x] **Material 3 Expressive (`m3x`) Adaptive UI** `1.2.0`
    - 3-state responsive layout (compact, medium, expanded), 7 palettes with cell-age shading, haptics, and EN/UK localization

---
## Phase 2 `Web, Deep Simulation & Sharing` 3/6
 - [x] **GitHub Pages Web Deployment** `1.2.1`
    - Automated Flutter Web build and deployment pipeline for instant browser play
 - [x] **LifeWiki Pattern Explorer & Heavy Stress-Test Patterns** `1.3.0`
    - 30+ curated LifeWiki patterns with search, author attribution, puffer category, centered loading, and external wiki links
 - [ ] **HashLife Ultra-Deep Simulation**
    - Quadtree memoized HashLife backend for exponentially fast stepping (thousands of generations per second)
 - [ ] **PNG / GIF / WebM Export**
    - Render high-resolution snapshots and animated loops directly from the simulation canvas
 - [x] **QR / Deep-Link Pattern Sharing** `1.2.1`
    - Encode compact RLE patterns into shareable URLs and QR codes for one-tap import
 - [ ] **Play Games Achievements**
    - Milestones for pattern discovery, generation counts, and custom creations on Android
