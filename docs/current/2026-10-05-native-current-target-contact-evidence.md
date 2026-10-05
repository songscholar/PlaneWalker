# Native Current Target Contact Evidence

- Status: Verified Locally
- Document Role: Current focused native contact and rollback evidence
- Authority Level: Approved P15 and standing project authorization
- Applies To: Same-frame Player movement, projectile retirement and physical contact sealing
- Owner: Native integration team
- Depends On: `../superpowers/plans/2026-10-05-native-complete-gameplay-certification.md`
- Last Verified: 2026-10-05

The production Main route refused a real Archer contact at runtime frame 1487. The native projectile query reported a hit at `(138.068909, 289.711853)` while the current Player circle was centered at `(119.824478, 285.855530)`, beyond the strict combined 17-pixel radius. The four-direction reproduction confirmed that `move_and_collide` updates the scene position before Godot's kinematic server transform. Transform notifications and explicit body-state writes did not change that same-frame query.

Preparation and commit now repeat the same native contact helper. Static-world motion excludes validated target bodies; actual current target CircleShape2D geometry is checked with Godot's shape collision API and its bounded segment-circle intersection. The earliest contact wins, equal-time world contact wins, previous pierced bodies remain excluded, and target identity, radius, full frozen trajectory and exact commit geometry remain required. No domain tolerance changed and no physical server state is rewritten.

Terminal source retirement also removes only retired projectile IDs from domain contacts. Original native contact seals remain in the ticket and are repeated against the before snapshot during commit. This fixes a separate confirmed terminal-overlap boundary; it was not sufficient by itself to resolve the Main refusal.

## Reproduction And Verification

- `build/test-evidence/native-terminal-projectile-contact-confirmed-red`: four terminal overlaps refused the stale contact; no parser or leak noise.
- `build/test-evidence/native-current-target-terminal`: four terminal overlaps pass exact payload/Registry rollback, restored native body, original-frame retry, one final death and no Player damage.
- `build/test-evidence/native-same-frame-target-hypothesis`: three of four movements refuse; physics server retains the previous Player center in all four cases.
- `build/test-evidence/native-current-target-ordered`: four directions and two actual wall/target orderings pass physical damage or no false damage, exact rollback, accepted retry and finite consumption.
- `build/test-evidence/native-current-target-overlap`: four initial overlaps settle actual Health, compensate and retry exactly once.
- `build/test-evidence/native-current-target-forge`: terminal Forge and real weapon-input regression pass.
- `build/test-evidence/native-current-target-domain`: strict trajectory, forged-contact and duplicate-piercing runtime regressions pass.
- `build/test-evidence/native-current-target-moth`: assertions pass for real walls, acid, piercing and lifetime. The strengthened generic engine-error gate correctly rejects intentionally injected refusal logs; explicit expected-error handling is a separate active harness task.

The bridge retains a detached diagnostic of the original rejected preparation across rollback. Its return values, transaction order, clock, RNG and publication semantics are unchanged. Diagnostic contexts are copied only when they are dictionaries.

Godot 4.6.1 was used. The focused passing scenes contain no script errors or leaks. The complete Main route has crossed the original contact boundary and is now separately investigating a later summon/preflight refusal. No complete, human or unassisted victory is claimed by this evidence.
