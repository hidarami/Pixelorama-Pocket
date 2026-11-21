# Touch layout (Android / iOS)

Pixelorama now has a touch-first layout. It is used automatically on Android and iOS, and it
only changes *where things are*: every tool, panel, menu entry, shortcut and extension is still
there, because the existing panels and menus are moved into slide-up sheets instead of being
rewritten.

## What it looks like

| Area | What it holds |
|---|---|
| **Top bar** | Menu (☰), project switcher, Undo, Redo, Layers & frames |
| **Canvas** | Takes the whole space in between. Rulers and the project tab strip are hidden |
| **Bottom bar** | Current color, Pencil, Eraser, Bucket, Color Picker, *All tools*, *Tool options* |

Everything else opens as a sheet over the canvas. Tap the dimmed canvas, press ✕, drag the sheet
down, or press the Android back button to close it.

* **Color**: color picker and palettes
* **Tool options**: Shift / Ctrl / Alt toggles, Copy / Cut / Paste / Delete, symmetry and the
  options of the current tool
* **Layers & frames**: the animation timeline
* **All tools**: a labelled grid of every tool (the bottom bar shows the current tool if it
  isn't one of the quick ones)
* **Menu**: File, Edit, Select, Project, Effects, View, Panels, Help. These are read from the
  existing menus, so items added by extensions appear too
* **Panels**: Canvas Preview, Reference Images, Perspective Editor, Recorder, Layer FX, Tiles,
  3D Object Tree, Second Canvas

The interface size can be changed in *Menu → Touch layout*.

## Switching layouts

* On a phone: *Menu → Touch layout → Use the classic desktop layout* (restart required).
  To come back, use *Window → Use Touch Layout* in the classic layout.
* On a computer, to try it out: `Pixelorama --mobile-ui` (or `--classic-ui` to force the old one).
  `PIXELORAMA_UI_SCALE=2.6` sets the interface scale for such a test.

## Where the code is

* `src/UI/Mobile/MobileUI.gd`: builds the bars and sheets, moves the panels
* `src/UI/Mobile/MobileSheet.gd`: the slide-up sheet
* `src/UI/Mobile/MobileMenu.gd`: the touch version of the top menu
* `src/UI/Mobile/MobileStyle.gd`: colors and touch sizes, derived from the current theme
* Small hooks in `Global.gd`, `Main.gd`, `TopMenuContainer.gd` and `SplashDialog.gd`
* Icons: `assets/graphics/mobile/` (Lucide, ISC license)

The desktop layouts are never modified or saved by the touch layout.

## Building the APK

* **In your fork, without a computer**: *Actions → Android APK → Run workflow*. Download the APK
  from the run's artifacts. (Workflow: `.github/workflows/android-apk.yml`.)
* **With the Godot 4.7 editor**: *Project → Install Android Build Template*, then
  *Project → Export → Android* (the preset already exists).
