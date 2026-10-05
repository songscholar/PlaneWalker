# Native Void Payload Identity

- Status: Verified Locally
- Document Role: Current focused native damage identity evidence
- Authority Level: Approved P15 and standing project authorization
- Applies To: Separate projectile receipts from independent semantic zone identities
- Owner: Native hostile integration team
- Last Verified: 2026-10-05
- Depends On: `../superpowers/plans/2026-10-05-native-complete-gameplay-certification.md`

Real Boss runs begin with attack generation 1. A later Tear zone uses its own payload identity and generation namespace. The damage preparation previously looked up every payload's generation as an owner attack, so a Tear tick could borrow the earlier Grasp receipt and reject effect commit. Existing auxiliary fixtures started at generation 7 and missed this collision.

Only a projectile present in the sealed native payload ticket inherits its owner's Void auxiliary receipt. Direct authored attacks retain their existing receipt path; independent semantic zones and burn ticks retain their own authenticated damage claims.

The focused generation-1 Grasp-to-Tear case failed at native frame 149 before the fix and passed afterward. It also checks that Tear creates no Grasp/Bolt/Devour/Scepter receipt and continues after a cold owner restore. Logs: `build/test-evidence/void-payload-identity-red` and `build/test-evidence/void-payload-identity-green`.

The four existing auxiliary domain/native/lifecycle suites are GREEN at `build/test-evidence/void-payload-status-regression`, including actual Bolt slow, Grasp slow, Devour output reduction, finite burn, pickups, cold restore and retirement. This is automated evidence; it certifies no human playtest or unassisted victory.
