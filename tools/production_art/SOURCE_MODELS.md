# Local 3D Sources to Pixel Actor Atlases

- Status: Implemented; external source assets pending
- Last Verified: 2026-10-06
- Scope: Optional local GLB/glTF, FBX and Blender source ingestion; technical previews

`source_model_pipeline.py` uses Blender CLI and Pillow. It makes no network
requests and does not access Tripo/Mixamo accounts, credentials or billing.
Run the command from the repository root. Source paths are relative to the
manifest, cannot escape its directory and are checked before Blender runs.
Install the pinned optional raster dependency with
`python3 -m pip install -r requirements-production-art.txt` when needed.

```bash
python3 tools/production_art/source_model_pipeline.py --help
python3 tools/production_art/source_model_pipeline.py inspect \
  tools/production_art/source_models.example.json
python3 -m unittest tests.contract.presentation.test_source_model_pipeline
SOURCE_MODEL_BLENDER_SMOKE=1 python3 -m unittest \
  tests.contract.presentation.test_source_model_pipeline
```

The example remains `awaiting_model`. `build` refuses assets marked
`awaiting_model`, `awaiting_animation` or `license_pending`. Ready sources need
an existing local file, `rights_status: approved` and a license record. External
Tripo/Mixamo sources additionally require the terms URL and acquisition date.
Use `sha256` to lock the exact source file. This records a rights decision;
it does not independently establish rights from a service's name.

## Offline Smoke Test

```bash
python3 tools/production_art/source_model_pipeline.py fixture \
  --output build/source-model-fixture
python3 tools/production_art/source_model_pipeline.py build \
  build/source-model-fixture/fixture-manifest.json \
  --output build/source-model-fixture/atlas
```

The fixture is locally authored cubes with simple object animation, exported
to GLB and FBX; opt-in smoke tests import and render both in Blender.
It is not a Tripo or Mixamo output and
is not a finished game character. `--blender /absolute/path/to/blender` can
select a Blender executable. Builds retain `blender.log` for diagnostics.

## Source Contract

- Characters use 48x48 frames; Bosses use 80x80 frames.
- IDs and kinds must match the existing actor runtime.
- States are `idle`, `move`, `attack`, `cast`, `hurt`, `death`, with four
  explicitly selected source frame numbers per state and 1-30 playback FPS.
- `render.resolution` is an integer multiple of frame size; the PNG renders
  use transparent film, fixed Cycles CPU samples/seed and Standard color view.
- `render.world_anchor`, `camera_direction`, `ortho_scale` and pixel `pivot`
  apply to the whole actor. The camera projects this world anchor to the fixed
  pixel pivot once. Individual frame bounds never change scale or centering.
- Nearest-neighbor downsampling, hard alpha thresholding, RGB palette matching
  without dithering and zero RGB in transparent pixels produce pixel frames.
- Empty, clipped, incorrectly sized and nonbinary-alpha frames fail packing;
  each state must contain at least three distinct rendered frames.

For a model with embedded animations, add `action: "ExactBlenderActionName"`
to the desired state. Omitting `action` uses the imported default animation
timeline. For a separate Mixamo FBX, add a state `source` object using the same
fields as the base source, plus the exact `action` name. Only one source and
one target armature with identical bone names and rest matrices are accepted.
The animation is transferred to the target rig; source meshes are hidden.
Prefer downloading an FBX animation made on the exact same uploaded character.
Changed proportions, Rigify conversion, locomotion root removal and general
retargeting require cleanup in Blender before this pipeline runs.

## Godot Handoff

Output contains `<actor_id>.png` and a `plane_walker_actor_atlas_v1`
`manifest.json`: four columns, six state rows, nearest filtering, existing
state/FPS metadata and SHA-256. It also records fixed pivot, frame bounds and
source/animation provenance. The manifest is structurally compatible with
`ActorAtlasProjection`; a partial preview does not replace the complete actor
library. Build into `build/` first, then merge reviewed actor descriptors and
PNGs into the production library in a separate reviewed change.

Godot's current sprite is centered by the runtime, so the pivot metadata
records the consistent location inside each cell; it does not automatically
change node position or gameplay collision. Match the existing baseline during
in-engine review before promotion. Generated atlases remain `technical_preview`
until native-scale silhouette, motion, weapon timing, death poses, skinning,
palette cohesion and actual gameplay background inspection pass. CPU render
hashes are expected to be stable for the same input, Blender version and host;
cross-version/renderer bit identity is not guaranteed. Normalization and PNG
packing are deterministic, as covered by contracts.

## Service Boundaries

[Tripo pricing](https://www.tripo3d.com/pricing) lists paid private/commercial
plans and a public free plan. The current free-plan marketing and
[Chinese terms](https://www.tripo3d.com/terms) differ on commercial usage;
keep sources pending until their actual applicable terms are recorded.
[Mixamo's FAQ](https://helpx.adobe.com/cn/creative-cloud/faq/mixamo-faq.html)
permits free commercial game use but restricts China-country-code Adobe IDs.
No external account, paid action or region workaround is required for the
offline fixture or the current pixel game to run.
