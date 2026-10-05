# Native Hound Sigil Evidence

- Status: Verified
- Document Role: Current
- Authority Level: Native implementation evidence below approved P15 specification
- Applies To: Eternal Hound dormancy, construct targeting, terminal publication and physical checkpoints
- Owner: Native hostile implementation team
- Last Verified: 2026-10-05
- Depends On: [mechanism plan](../superpowers/plans/2026-10-05-native-hound-phase-mechanisms.md)

## Retained Behavior

The existing species state owns one 300-frame dormancy, one-HP principal,
12-HP sigil and duplicate damage claims. An Actor-owned native Area2D exposes
the sigil to the ordinary Sword, Bow, Gun, Staff and Gauntlets producers.
Weapon target policy classifies it as a construct and stops dormant principals
from intercepting projectiles. The sigil neither joins the enemy group nor
owns a second Health or reward authority.

Authenticated Player components mutate sigil HP independently by damage type.
Its final component settles the original principal through normal Health
publication, with a synchronous, object-identity-scoped settlement context.
Sealed-frame rejection restores species, Health, claims and physical
targetability. Cold reconstruction derives the same sigil from existing state
without changing the Actor envelope, content catalog or pack fingerprints.

Eight live sigils consume the shared construct budget. A ninth lethal is
refused without consuming HP, dormancy or damage identity; the same hit retries
after a slot releases. Stop leaves the authored dormancy clock unscaled.
Reform occurs after exactly 300 frames and cannot reopen a used dormancy.
Shielded settlement adds no shield claim, and authored Splitting exclusion for
Hound child ownership remains intact.

## Validation

- `build/native-hound-affixed-final`: native sigil integration passed, including all five physical weapon producers, mixed damage components, eight-slot refusal/retry, Shielded finalization, rollback, typed cold reconstruction and Stop-unscaled reform.
- `build/native-hound-sigil-checkpoint-verified`: actual seeded Host route, physical Profile/SaveService reconstruction, partial sigil damage, paid ordinary Rewind receipt and final restored Sword kill.
- `build/native-hound-complete-enemy-final`: complete enemy runtime regression, 1/1 passed.
- `build/native-hound-summon-final`: native summon lifecycle, payload, actual weapon input and domain regressions, 4/4 passed.
- `build/native-hound-sigil-visual-retained.log`: native Metal raster QA at 640x360 and 1280x720; screenshots retained in `build/visual-evidence/native-enemy-mechanisms/`.
- Pinned production-art, developer and coverage requirements pass `pip-audit` with no known vulnerabilities.
- `build/native-hound-retained-tests`: clean Git archive `1739afa` imports and passes both native sigil and physical checkpoint suites, 2/2.
- `build/native-hound-rift-projection`: sigil geometry remains valid after ordinary Rift changes, with the five-weapon and dormancy regressions, 1/1.

Godot logs are checked for script errors and leaked engine objects. The
installed Godot 4.6.1 executable cannot collect GDScript line coverage; scene
assertions provide the executable evidence. Physical tests require fresh
`TEST_LOG_DIR` user-data paths because successful checkpoints intentionally
retain an active Profile launch.

## Recovery And Assets

Original CC0 raster atlases, their SHA-256 manifest and reproducible Pillow
generator live under `assets/production/enemy_mechanisms/` and
`tools/production_art/generate_enemy_mechanism_atlases.py`. The generator also
supplies the planned Phase Ranger arrival atlas. Removing the sigil Actor
hooks and target-policy registration reverses this presentation integration;
existing domain dormancy snapshots remain readable.
