# Native Owned Frame Token Plan

- Status: Draft / Current
- Document Role: Current focused ownership investigation and proposed executable protocol
- Authority Level: Below approved full-product completion contract
- Applies To: Genuine native Actor and Boss frame preparation through HostileFrameBridge
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-legacy-action-digest-evidence.md`
- Last Verified: 2026-10-06

## Concrete Copy Path

`LaunchHostileActor.prepare_launch_frame` currently deep-copies the complete
before/after ticket into private retention and again into the public result.
Boss postprocessing deep-copies the complete adjusted ticket again, and Bridge
deep-copies that public ticket into its record. Late Boss snapshots contain
growing history/claim arrays, so these copies scale with run history. Effects
consume detached action batches rather than the Actor before/after snapshots.

Keep the required pre-weapon Bridge checkpoint: Player weapons and controls can
change the Actor before hostile preparation. The later candidate's `before`
cannot replace that earlier compensation point. Keep runtime restoration,
validation, gameplay history, recorder contents and all physical capacities.

## Proposed Interfaces For Root Review

The proposed opaque class is
`scripts/enemies/launch/native_hostile_frame_token.gd`, extending `RefCounted`
with no candidate, dictionary, array, owner or frame fields. A token's class,
copied properties or supplied identity cannot authenticate it. Only exact
instance equality with the Actor's active marker authenticates issuance.

| Owner | Method | Contract |
| --- | --- | --- |
| Actor | `supports_native_launch_frame_protocol() -> bool` | True only for the exact migrated HostileActor and BossActor scripts |
| Actor | `prepare_native_launch_frame(frame, observations, authority) -> Dictionary` | Success fields in order `ok`, `token`, `batch`; batch is detached |
| Actor | `owns_native_launch_frame_token(token, authority) -> bool` | Exact active instance, captured bound Bridge and active frame/roster |
| Actor | `can_commit_native_launch_frame(token, authority) -> bool` | Original complete live-before/Health/restore/landing/Boss guards |
| Actor | `commit_native_launch_frame(token, authority) -> bool` | Same independent domain restoration and committed phase |
| Actor | `rollback_native_launch_frame(token, authority) -> bool` | Original candidate compensation, then marker revocation |
| Actor | `can_publish_native_launch_frame(token, authority) -> bool` | Original committed, room, landing and Boss safety guards |
| Actor | `publish_native_launch_frame(token, authority) -> bool` | Original cleanup and visual update, then marker revocation |
| Bridge | `owns_native_actor_preparation_context(actor, frame) -> bool` | Exact currently executing prepare call and active genuine record |
| Bridge | `owns_native_actor_frame_context(actor, token, frame) -> bool` | Active prepared frame, exact bound roster/registry/run and same record marker |

Names and record fields remain proposed until Root review. Native tokens are
not serialized or accepted by save/replay interfaces. Native failures retain
the established Actor failure structure and refusal behavior.

## Authority And Migration

Actor retains one privately owned candidate and one empty marker. Native
preparation must be authorized by the exact configured Bridge, verified through
the bound frame provider/registry and Bridge's active Actor record. Capture
the authority without a strong ownership cycle. The marker is issued only
after every Boss postprocessing branch succeeds. No native method returns
mutable `before`, `after`, `health_before` or retained ticket references.

Refactor the existing Actor preparation body into a shared private owned
preparation hook that returns only success/failure. It adopts its independently
constructed candidate once. The existing public `prepare_launch_frame` remains
a wrapper exporting the full original detached ticket and detached batch,
with unchanged field order, Variant types and live Node identities.

Move the Boss public preparation override to the private owned hook. Preserve
preparation geometry checks and exact Forge, Forest, Void, Ruin wall and charge
postprocessing. These private branches adjust the one retained candidate and
finish before public export or native token issuance. Forest commit/publication
checks still dispatch through the existing Boss overrides. Do not bypass them
by directly calling the base implementation.

Bridge's private record adds `native_actor_frame` and `actor_token`, retaining
the existing `actor_ticket` for legacy participants. Opt in only when the
complete native protocol is present and support is explicitly true. During
the prepare call, expose only the exact current Actor as a transient native
preparation context, then clear it before continuing or refusing. Native
records pass the token back to the same Actor for all original lifecycle
operations; legacy records retain their existing dictionary calls and copies.
Native frame context must also compare the supplied marker with the exact
marker retained in that record. Checking owner/frame alone can reauthorize a
held old marker when a compensated frame retries with the same frame number.

`LaunchSummonActor` overrides public preparation to enforce its real lease and
perform retirement damage. `LaunchOrdinaryCopyActor` inherits that override.
Both must remain on the old path in this slice, as must unknown subclasses and
test doubles. Inheriting native method names alone must never opt them in.
An actor that claims native support but returns an invalid native result fails
closed; it must not silently retry public preparation after partial work.

Keep Effects, payload, semantic and summon protocols unchanged. Native Bridge
still supplies a detached small batch. Effects retains its exact comparison
against `prepared_launch_frame_batch()` during preparation and commit. That
batch getter stays detached. Existing private projections may read the retained
candidate internally; no new mutable reference crosses the native token API.

## Lifecycle And Failure Boundaries

The active marker survives accepted candidate commit until the existing Actor
publication cleanup. Candidate rollback, full transaction restoration, public
publication, completed cleanup, configuration changes and authority replacement
must invalidate it. Failure before token issuance grants no marker. A held
marker cannot keep an old candidate alive or restore it after revocation.
Repeated prepare/commit/publish, consumed tokens, another Actor's token, another
Bridge, wrong frame, changed roster, invalid/freed owner and reentrant calls
must refuse without consuming valid compensation rights.
Native mutating lifecycle methods also need a transient operation guard so a
reentrant callback cannot enter the same operation before phase flags settle.
The guard is separate from the public dictionary API and must clear on every
normal success or refusal return.

Token identity supplements authority rather than replacing live equality and
strict restore checks. Real Health, room, teleport/phase landing and Forest
cage drift remain visible. Post-commit Effects may legitimately settle damage
receipts in live runtime; preserve the original publication semantics rather
than inventing a full after-snapshot equality requirement.

Bridge rollback still restores the original pre-weapon Actor transaction
checkpoint, even if candidate rollback already occurred or preparation failed
before token issuance. A failed compensation returns false and cannot publish
or advance the frame. The existing Bridge clears active records even when a
rollback participant fails; changing that recovery policy is outside this
slice unless Root explicitly broadens it. No failure may manufacture a fresh
token or bind an old pending marker to a later record. Sealed publication revokes Actor
markers before later observer callbacks, preserves exactly-once Effects/Health
signals and refuses reentrant frame starts while publishing.

## Executable Criteria

Before production changes, a real native fixture must fail only the missing
owned protocol assertions while existing full public preparation, detached
mutation refusal, actual Node identities, rollback and next-frame behavior pass.
It uses authored native rooms, ordinary Actor, five Bosses and genuine committed
historical Void/Time Actions, a real Player, Bridge, Registry and Effects.

GREEN must prove genuine native Bridge records retain only the empty marker,
not a whole public Actor ticket. Public results retain exact field order and
complete detached before/after/batch/Health branches. Native retained candidate
bytes match an equivalent public preparation through rollback/retry, aside
from fresh ticket identity. Fake/foreign/stale markers, changed owner/context,
live-state drift and nested public mutation must never poison canonical state.
Summon and copy lease refusals and generic legacy participants retain the
public fallback. Warm tokens revoke on rollback and publication, retries issue
new markers and failed siblings publish no observations.

Before acceptance, extend focused cases for reentrant preparation/publication,
rollback failure, live landing/cage/Health drift, same-frame death, affixes,
summon roster changes, late World/Effects refusal and actual collision contacts.
Run Actor candidate typed/order tests, current/historical Boss and native
transaction regressions, the Bridge fallback/compensation suite, complete save
checkpoints and physical replay neighbors. Retain scoped strict paired logs.
Measure the actual late native copy path before/after; configuration counts
or removed source calls cannot certify the 16.667-ms frame budget.

## Ownership And Sequence

Prospective production ownership is limited to `LaunchHostileActor`,
`LaunchBossActor`, `HostileFrameBridge` and the new empty token class. UI lane
owns the independent Effects snapshot slice. Root owns BossRuntime parent
restoration and integrated measurement. No production edit or staging is
authorized for this slice until Root resolves these proposed interfaces and
reviews the focused RED. Rendered throughput, sustained recording, saturation,
the 45-minute soak, complete UI and human playtesting remain open.
