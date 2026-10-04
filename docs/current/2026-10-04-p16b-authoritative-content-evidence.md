# P16B Authoritative Hub Content Evidence

- Status: Focused content boundary GREEN; production activation pending
- Document Role: Current P16B focused content verification evidence
- Authority Level: Evidence beneath the approved P16 specification
- Applies To: Five P16 catalogs, closed JSON schemas, bilingual source catalogs, and Python contracts
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`, `docs/superpowers/plans/2026-10-04-plane-walker-p16-hub-meta-narrative.md`
- Last Verified: 2026-10-04

## Authored content

The five JSON catalogs contain 156 entries: 42 Meta nodes, three Hub districts,
20 forge definitions, 57 narrative definitions, and 34 tutorial definitions.
Each entry has one closed schema_version 1 shape with no arbitrary runtime
scripts or combat effect dictionaries. Unknown nested authored fields are
rejected, including objects inside arrays.

- Meta: W/C/L/F/P branch counts 10/8/10/8/6; exact approved costs and acyclic
  prerequisites; P-04 requires P-01 and L-09. Cumulative stat totals are maximum
  HP 5%, entrance healing 2%, Void reduction 2%, attack 3%, attack speed 2%.
  Their direct budget sums to 14%, below the approved 15% maximum.
- Hub: three districts expose nine unique functions. Scene paths are authored
  descriptors; native scene creation and interaction are later P16 work.
- Forge: five canonical weapons, five deterministic levels each with costs
  5/10/20/35/50 shards and +1% attack per level; five proficiency thresholds;
  fifteen EN-01..EN-15 preferences. Element and time/Void groups are mutually
  exclusive. Preferences add no new permanent combat proc.
- Narrative: eight NPCs and 104 dialogue nodes; ten independent artifacts;
  E1-1..E1-5 and E2-1..E5-4 total twenty-one environment records; three ordered
  five-step hidden lines; five exact ending predicates; five Nemesis encounters
  and five Vera conversations. Three distinct NPC floor choices provide
  `balance_choice_*` flags for the balance ending's durable source accounting.
- Onboarding: ten lessons, fifteen implemented-topic hints, six repeatable
  training tasks with one-time first completion rewards, and three explicitly
  optional assisted run definitions at damage 0.80/0.90/1.0 and warning scale
  1.25/1.10/1.0. Every assisted run is excluded from ranked eligibility.
- Both existing localization source CSVs contain the same 537 unique P16 keys
  with complete English and Simplified Chinese text. Text includes NPC arcs,
  collection descriptions, journal steps, endings, credits, and choice labels.

## Data contracts

Global Meta entry IDs are `meta_w_01` etc.; canonical legacy domain IDs are
preserved in `node_id` (`W-01` etc.). The Meta domain projection is
`{id: node_id, branch, cost, prerequisites, effects: meta_effects}`.

Narrative kind-specific IDs use `npc_id`, `artifact_id`, `record_id`,
`storyline_id`, and `ending_id`; their global Registry IDs are lowercase.
Closed predicates use `{kind, id, value}`. Dialogue choices use the consumed
node source, explicit affinity/faction deltas, flags, and `once: true`.
Runtime adapters must consume no more than one choice from each source.
`balance_choice_*` flags contribute one durable balance source each.

Hidden steps require the immediately previous step and actual authored
record/affinity/count facts where applicable. Pickup receipt identities carry
the historical letters rather than requiring additional ungrantable flags.
The Void line needs 18,000 active gameplay frames (five minutes at 60 Hz),
excluding pause, menus, and Hub time in its later runtime adapter.

Vera choices occur only on the canonical throne floor. `listen` grants sixteen
affinity and consumes its profile source once, with a five temporary maximum-HP
cost in the active run. `defer` grants no affinity, faction change, or flag and
does not consume its source. Native affordability, refusal-to-kill, and reload
compensation remain runtime gates rather than content-test claims.

## Verification

RED was recorded before creating catalogs: missing authoritative JSON sources.
After narrative creation, localization verification was RED until all referenced
keys were authored. Final command:

```sh
python3 -m unittest tests.contract.content_schema.test_p16_hub_schemas
```

Result: 9/9 GREEN on 2026-10-04. Contracts cover every closed nested object,
exact authored counts, prerequisite cycles, costs and stat budgets, option
references, ending predicates, unique source receipts, side-effect-free Vera
defer, three distinct balance sources, and bilingual catalog equivalence.

`python3 tools/validate_localization.py` was also run. P16 produced no missing
keys or placeholder mismatches. The whole-tree command reported 54 missing
Enemy/Boss name/description keys in concurrently authored inactive P15 catalogs;
the P15 owner retains their draft-localization activation boundary. This is not
a whole-tree localization GREEN claim.

## Remaining integration gates

The five catalogs are inactive until reviewed Registry/pack projections and
hashes are installed by the integration lead. Production Meta fixtures must
then project from the same JSON; duplicate production tables are not permitted.
Native Hub scenes, gameplay source receipt generation, dialogue execution,
training progression, save migration, actual ending/credits playback, physical
Save/Replay, visual/controller QA, and offline export are later P16 boundaries.
This evidence certifies authored content only, not complete P16 gameplay.
