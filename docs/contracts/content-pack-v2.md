# Plane Walker Content Pack v2 Contract

- Status: Frozen / Current
- Document Role: Current contract
- Authority Level: Versioned content-pack and declarative-effect contract
- Applies To: Base game, first-party updates, Mods, DLC, localization, approved assets, and deterministic content snapshots
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/contracts/save-service-v2.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`, `docs/superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md`
- Last Verified: 2026-10-01
- Schema version: `2`

## Purpose

The base game, first-party updates, Mods, and DLC use the same versioned content-pack envelope. A pack is data, localization, and approved assets; it is never an arbitrary script delivery mechanism.

## Pack identity and paths

`pack_id` matches `^[a-z0-9][a-z0-9_-]{0,63}$` so it can be stored in the frozen SaveService snapshot format. Content IDs match `^[a-z0-9][a-z0-9_.-]{0,63}$`. Pack-relative paths use `/`, may not be absolute, and may not contain `..`, empty segments, or a GDScript extension. IDs and released pack versions are immutable identities.

Every `pack.json` requires:

- `pack_id`
- `pack_version`
- `schema_version`
- `game_version_range`
- `dependencies`
- `load_order`
- `content_manifest`
- `localization_sources`
- `asset_manifest`
- `integrity_hashes`
- `entitlement_tag`

## Dependency and activation rules

Deterministic activation resolves dependencies before load order; ties use ascending `load_order`, then `pack_id`. A missing required dependency, incompatible version, duplicate pack ID, or dependency cycle rejects the pack before any content becomes visible.

The base pack is required and failure is blocking. Optional pack isolation removes an invalid Mod, DLC, or first-party optional pack and every dependant that cannot remain valid, while preserving unrelated activated packs. Diagnostics identify the rejected pack and reason.

## Integrity hash rules

Every file named by the content manifest, localization source list, or asset manifest has a lowercase SHA-256 integrity hash. The loader closes and re-reads files before comparing hashes. Integrity detects corruption and accidental drift; it is not a cryptographic anti-cheat guarantee.

## Content entry rules

Entries have a stable ID, category, availability list, localization keys, tags, compatibility constraints, and declarative effects. Unknown root fields are rejected. Cross-references must resolve inside the activated pack set. Localization keys must exist in every required locale before the entry is eligible.

Effects use a closed engine-owned handler catalog. Content may supply scalar parameters only. An arbitrary script path, script resource, callable name, or executable expression is forbidden and blocks the owning required pack or isolates the owning optional pack.

### Registered specialized schemas

The generic `content_entry_v2.schema.json` contract remains frozen. Domains whose nested structure cannot be represented safely as generic scalar effects are registered as specialized manifest rows and dispatched by `ContentRegistry` before generic-entry validation:

| Category discriminator | Schema | Runtime parser |
|---|---|---|
| `floor_definition` | `floor_definition_v1.schema.json` | `FloorDefinition` |
| `room_template` | `room_template_v1.schema.json` | `RoomTemplateDefinition` |
| `dungeon_event` | `dungeon_event_v1.schema.json` | `DungeonEventDefinition` |
| `merchant_definition` | `merchant_definition_v1.schema.json` | `MerchantDefinition` |
| `economy_profile` | `economy_profile_v1.schema.json` | `EconomyProfile` |
| `cosmetic_definition` | `cosmetic_definition_v1.schema.json` | `CosmeticDefinition` |

Each specialized row declares `category`, stable `id`, `schema_version: 1`, and availability. Its parser rejects unknown root fields and normalizes only closed declarative data. Nested keys whose field name ends in `_key` are localization references and must resolve through the candidate pack's localization sources. IDs in registered reference fields must resolve against the same candidate activated-pack set or the closed P14 encounter-adapter taxonomy.

Specialized rows receive the same integrity hash, pack-level ID uniqueness, dependency isolation, no-executable-content, localization, cross-reference, deterministic activation, and immutable deep-copy guarantees as generic rows. A parser, localization, or reference failure rejects the complete required pack or isolates the complete optional pack; no partial candidate definitions become visible.

## Localization and assets

Each localization source is declared by a safe relative path and covered by the integrity map. The loader validates required language keys after all dependencies activate. The asset manifest contains safe relative paths plus approved asset kinds; no asset record may redirect outside the pack root.

## Entitlements and offline behavior

The entitlement tag (`entitlement_tag`) is metadata consumed by a provider adapter. The base pack uses an empty tag. Missing online entitlement services do not disable base-game play; development and offline modes use explicit local entitlement fixtures.

## Deterministic snapshots

The active registry exposes a sorted row for every pack: `pack_id`, `pack_version`, `schema_version`, and SHA-256 digest. Rows sort by `pack_id`; canonical JSON of the rows produces the aggregate digest stored by SaveService and Replay.
