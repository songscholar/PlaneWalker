# P20B Offline Local Run Records

- Status: Approved / Current
- Document Role: Current implementation specification
- Authority Level: Focused implementation scope
- Applies To: Physical settled Profile, local records storage, Main and Hub mirror
- Owner: Runtime integration lane
- Depends On: `2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-10-05

Only `ProfileRuntimeService.verified_local_record_outbox()` may supply pending records. It reads the exact durable primary and authenticates each source through settlement authority, comparing Run/sequence/reason and receipt digest against the saved launch, terminal facts and Profile lineage. Its legacy `verified_settled_run()` fallback refuses active or abandoned receipts. Both return detached content, configuration, terminal facts and receipt. Caller dictionaries and arbitrary provider callbacks cannot enter the record writer.

Settlement saves each original content binding, launch, terminal and settlement receipt in `local_records_outbox` with the core Profile transaction. Launch and abandon preserve pending sources. The pending queue retains at most 1000 sources using the same deterministic ranking as the board; overflow increments the bounded `omitted_count` and never refuses the core settlement. The schema-1 extension accepts older two-field payloads with an implicit zero omitted count. It is a bounded local record queue, not a complete permanent run archive.

An independent schema-1 board is persisted with SaveService, without changing MetaProfile. The board identity includes the entire actual content snapshot and save domain. Entries are ranked by `completed_floors * 100000 + completed_rooms * 1000 + victory * 1000000`; smaller positive run time then stable identity break ties. At most 1000 entries and 1000 Profile watermarks are retained. Watermarks include the complete Run ID and settlement digest, so evicted records remain consumed. Same-sequence conflicting identities fail closed; older already consumed sequences cannot re-enter.

Writes compare the durable primary at the promotion boundary. This detects interleaved writers within the running process and is not a cross-process atomic file lock. Pre-promotion faults retain board memory; an independently inspected primary equal to the candidate is the only post-promotion commit proof. Acknowledgement additionally validates the complete board protocol, canonical content/domain board ID, and a watermark equal to an authenticated queued source no later than the Profile launch sequence. Only then does a separate Profile compare-exchange remove consumed sources, without changing Meta revision or currency. Failed acknowledgement retains the queue for retry.

Save failures are optional capability failures and never block the playable game. Main startup, authentic settlement, and the actual Hub refresh control retry synchronization, including after another run has launched and after a fresh Main physically reloads the Profile. Read-only refresh during an active run reloads the current physical board. Content and Mod domains never share boards; historical queued sources publish under their original binding. All boards are local, and Mod boards explicitly say Local / Unranked.

Completion requires meaningful RED and GREEN physical tests for restart, exactly-once, ranking, truncation, storage fault points, reentrant refusal, forged terminal/durable mismatch, domain/content isolation, actual Main death settlement, Hub refresh and displayed entries. Native presentation must retain controller focus and fit supported viewports. Daily challenge, Boss Rush and endless mode are later domains and are not represented by fabricated records here.
