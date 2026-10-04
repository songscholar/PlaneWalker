# P17C Launch Enemy Presentation Evidence

- Status: Approved / Current
- Document Role: Current focused enemy raster and native scene verification evidence
- Authority Level: Verification below P15 hostile and full-product specifications
- Applies To: Twenty-two original phase rasters and eighteen missing native scenes
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/plans/2026-10-05-plane-walker-p17c-launch-enemy-presentation.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Complete native scene library and focused presentation verified; species mechanics and combined production combat remain separate active gates
- Exit Gate: Reproduction, imported native library, rendered inspection and actual PCK scene fixture pass without errors or leaks

The authoritative EnemyDefinition catalog supplies all twenty-two identities,
Health values, movement speed and new-scene collision radii. Original transparent
192x48 pixel atlases use four 48x48 cells for idle, warning, active and recovery.
Each species has a separately authored silhouette. Floor palettes, weapon shapes,
eyes, shells, antlers, wings, roots and limbs distinguish roles at native scale.
The deterministic Pillow renderer, content-derived scene source, SHA-256 manifest,
CC0 provenance and contact sheet are retained with the assets.

Eighteen previously missing canonical scene paths now instantiate the existing
LaunchHostileActor with real HealthComponent, Hurtbox and circular body geometry.
The four certified legacy scenes and their original assets remain byte-identical.
Their visible rasters continue to load; the new library also retains original
replacement artwork for those four identities. Base descriptor and compatibility
ledger identities are unaffected by this additive presentation milestone.

## Verification

- Missing-library RED: both Python asset contracts failed before generation.
- Missing-native-scenes RED: `build/test-logs/p17c-enemy-library-red`, only 4/22 canonical scenes existed.
- Python asset contracts: 2/2 GREEN; all files and all eighteen generated scenes reproduce byte-for-byte; all twenty-two alpha silhouettes are unique, all four frames differ, and every cell has transparent padding and more than eighty visible pixels.
- Actual Godot import: `build/test-logs/p17c-enemy-import.godot.log`, no errors or leaks.
- Native library: `build/test-logs/p17c-enemy-library-green`, 1/1 GREEN, all twenty-two native actors expose hostile APIs, original Health, exact new collision radii, actual imported textures and nearest filtering.
- Actual OpenGL window: `build/test-logs/p17c-enemy-window.godot.log`, clean PASS; `build/visual-evidence/p17c-enemy-art/native-enemies.png` was inspected at the actual 640x360 viewport. Every actor and localized name is visible with no overlap or clipping. The retained contact sheet shows all eighty-eight original phase cells.
- Actual PCK export and packed fixture: `build/p17c-enemy-library.pck`, `build/test-logs/p17c-enemy-export.godot.log`, `build/test-logs/p17c-enemy-packed.godot.log`, clean PASS. All canonical scenes and imported enemy textures load from the pack.

This milestone certifies presentation and resource availability. It does not
certify every species mechanism, elite affix, Boss effect, completed playthrough
or full-product package. The focused additive commit is independently reversible;
ongoing combat work uses the same canonical paths and content definitions.
