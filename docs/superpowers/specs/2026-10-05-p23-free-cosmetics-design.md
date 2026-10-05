# P23 Free Cosmetic Collection

- Status: Approved
- Document Role: Current implementation specification
- Authority Level: Milestone design under standing project authorization
- Applies To: Free character appearances and native Hub gallery
- Owner: Plane Walker project owner
- Depends On: `../../../AGENTS.md`, `2026-10-05-p22b-replay-library-design.md`
- Last Verified: 2026-10-05

The native Hub gallery retains discovered items and gains fifteen free character appearances: the original, first-return and first-victory appearance for each of the five launch characters. The latter two routes require durable finished-run and victory statistics, respectively, plus ownership of the character. There is no purchase, random draw or combat effect.

One authored `cosmetic_definition` catalog defines appearance identity, character, unlock route and the actual raster atlas digest. This specialized discriminator preserves the frozen generic content-entry contract. Preview and gameplay use those same atlases. Original artwork is generated deterministically from the existing original CC0 character source. No external artwork or remote service is required.

The existing Meta Profile shape, legacy `cosmetics` references and Meta catalog fingerprint remain stable. A separately versioned `cosmetic_collection` payload owns claimed appearance IDs and equipped IDs by character. Its catalog fingerprint authenticates the independent appearance catalog. A missing payload denotes the original appearance. Commands increment the existing Profile revision, consume the existing bounded Profile command history and use the actual Save promotion transaction; failed promotion cannot publish collection or equipment.

Physical Save validation rejects unknown appearances, cross-character equipment, unclaimed equipment, locked claims, forged progress, invalid hashes and malformed nested payloads. Active native runs prevent cosmetic changes so a retained run cannot change appearance midway through a recovery. Optional cosmetic presentation never mutates Player, Health, weapon, replay or World domain state.

Completion requires failing tests before implementation, strict catalog/content/save contracts, actual promotion fault and cold-reload tests, native gallery controls and preview, launch/resume presentation integration, both locales, keyboard/controller flow, raster pixel evidence and retained reproducible build documentation.
