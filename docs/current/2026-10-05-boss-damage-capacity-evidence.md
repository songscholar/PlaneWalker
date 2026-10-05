# Native Boss Damage Capacity Evidence

- Status: Verified focused repair
- Document Role: Current retention evidence
- Authority Level: Evidence below approved P15 specification
- Applies To: Native Boss body admission, finite receipts and typed cold recovery
- Owner: Native hostile implementation team
- Last Verified: 2026-10-05
- Depends On: [Native Body Settlement Evidence](2026-10-05-native-body-settlement-evidence.md)

## Reproduced Defect

The previous 512-receipt native body admission boundary refused component 513
while the maximum endless Void Boss still had 8488 HP. The fixture delivered
real DamageInfo through the actual Boss HealthComponent. RED evidence is
`build/test-evidence/boss-damage-capacity-red-actual`.

## Retained Repair

Boss damage receipts have a separate finite capacity of 10000. Other Boss
receipt categories retain their existing 512 limit. No settled damage identity
is evicted. Strict cold restoration accepts the expanded damage ledger and
still refuses invalid, repeated or oversized entries.

The actual native Health boundary floors each positive resolved hit to one HP.
Boss difficulty caps HP scaling at 3.0: the largest Boss is 3000 * 3 = 9000 HP.
Authored Forest drain healing is capped at 200 per encounter and Traitor rewind
healing at 300; other Bosses do not heal their bodies. Even a conservative
9000 + 300 minimum-hit bound remains below 10000. Void core damage can only
reduce the required body hits. A future content or healing-cap increase must
revise this finite capacity contract and its executable gate.

A private reusable body preview still restores and validates the entire current
snapshot for each admission. Definition reconfiguration clears it. Historical
alias lookup constructs a local claim set once per admission, preserving all
old direct and double-hashed receipts while avoiding repeated linear scans.

## Executable Evidence

- `build/test-evidence/native-body-capacity-extended`: GREEN 1/1, including capacity 10000, refusal at 10001, no eviction and typed cold restoration.
- `build/test-evidence/boss-damage-capacity-green`: GREEN 1/1, all 9000 real minimum-damage hits defeat the actual maximum endless Void Boss.
- `build/test-evidence/native-body-preview-cache`: GREEN 1/1, full native body settlement regression after preview reuse.
- `build/test-evidence/boss-damage-capacity-cached`: GREEN 1/1 in 240.77 seconds. The oldest hit remains spent past 512 and after fresh typed reconstruction; terminal Health and Boss state agree.

The test runner reserves 600 seconds for the native Boss capacity stress scene,
including its use by the instrumented coverage provider. Focused tests do not
collect engine line coverage. Combined immutable-source certification remains
separate.
