# Native Projectile Overlap Evidence

- Status: Verified Locally
- Document Role: Current focused native contact and compensation evidence
- Authority Level: Approved P15 and standing project authorization
- Applies To: Moving target overlap, deterministic trajectory, actual Health and strict contact sealing
- Owner: Native hostile integration team
- Last Verified: 2026-10-05
- Depends On: `../superpowers/plans/2026-10-05-native-complete-gameplay-certification.md`

The actual five-floor run reached floor index 2 and refused Rift Weaver's physical contact at frame 5993. A Player entering a live projectile can trigger Godot overlap recovery. `KinematicCollision2D.get_travel()` then includes recovery perpendicular to or outside the authored sweep; the strict domain correctly rejected that raw value as a trajectory point.

Native preparation now projects the impact onto the original bounded sweep. Its sealed physical ticket retains the complete original recovery travel and collider and repeats the same Godot query before commit. Target radius validation, frozen trajectory checks, exact claims and pierce limits remain required. No domain contact tolerance was widened.

- RED: `build/test-evidence/native-projectile-overlap-red`, four actual overlapping target directions refused the native frame.
- Diagnosis: `build/test-evidence/native-projectile-overlap-diagnostic`, recovery travel was 7.89975 pixels outside the 2.66667-pixel sweep.
- GREEN: `build/test-evidence/native-projectile-overlap-health-verified`, four overlaps settle the approved elite 15 damage, compensate the full native flight and Player Health, retry once and cannot hit again.
- Domain contract regression: `build/test-evidence/native-projectile-contract-regression`, 1/1, including forged off-trajectory contacts and duplicate piercing rejection.
- Wall and finite acid regression: `build/test-evidence/native-projectile-world-regression`, 1/1.
- Two-body actual piercing regression: `build/test-evidence/native-projectile-piercing-regression`, 1/1.

Evidence uses Godot 4.6.1 with script/error/leak scans. Full native route certification continues separately and no human or unassisted victory is claimed here.
