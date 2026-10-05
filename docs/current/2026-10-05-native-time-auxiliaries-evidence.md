# Native Time Sovereign Auxiliary Evidence

- Status: Focused Verified / Current
- Document Role: Current retained implementation evidence
- Authority Level: Evidence subordinate to approved P15 and Full Product scope
- Applies To: Regular Time Sovereign Slash, Bolt, Blink, Freeze and Collapse auxiliary mechanics
- Owner: Project implementation agent
- Depends On: `AGENTS.md`, `../superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Last Verified: 2026-10-05
- Retained Source: `ecc8a8b`
- Exit Gate: Exact archived source9/9GREEN, native raster checks, finite lifecycle and physical Save/Replay continuation equality

## Retained Behavior

Authentic accepted Slash HP loss installs one source-owned Time damage mark:1.15,
240 accepted frames, refresh without stacking and exclusive expiry. Player applies
the strongest active mark to every Time hit before flat defense. Prevented hits
cannot mark. The native clock raster appears over Player and retires on owner death.

Authentic physical Bolt contact reserves a shared-budget r16 slow zone lasting180
accepted frames, movement0.70 and no extra damage. Synthetic unsealed contacts
refuse. Leaving the zone restores ordinary movement on the next accepted frame.

Blink locks Player facing independently from Boss approach, completes all35
warning frames and arrives48px behind that frozen facing only when the physical
world and bodies permit it. Subsequent Slash retains its full35frame warning.

Freeze retains its authored r80 field,0.40 movement and all time input. Regeneration
is0.50 inside the active field; leaving, expiry and disposal remove this modifier.
Actual60fixed frames grant exactly half the normal per-second regeneration.

Collapse accepted HP loss removes at most10energy, leaves at least1 when starting
above1 and preserves positive fractional energy below1. Prevented damage costs0.
Late refusal restores exact HP, energy, resource revision, receipts and modifiers,
and publishes no early resource observation.

Boss schema10 retains deterministic auxiliary receipts. Exact historical schema1
and9 normalize with empty auxiliary state; schema9 keeps its authentic paid-response
ledger. Missing current state, unknown historical fields and clock drift refuse.
Physical Save/typed Replay restore real Boss, Effects and full Player into a fresh
world; their next accepted states exactly match uninterrupted continuation.

## Verification

The independent archive is `build/test-source/time-auxiliary-retention`, generated
from retained commit `ecc8a8b` and imported without current peer changes. Its suites
pass9/9scene tests:

- Auxiliary native and auxiliary/response domain: `build/time-auxiliary-retained-domain-native`3/3.
- Native Time response: `build/time-auxiliary-retained-response`1/1.
- Shared projectile domain: `build/time-auxiliary-retained-payload`1/1.
- Actual production Profiles: `build/time-auxiliary-retained-profile-{stop,rewind,accelerate,rift}`1/1each.

Final passing logs contain only injected World refusals35/120(auxiliaries) and
61/130(existing response tests). No script errors, parse errors or leak diagnostics
occur. A second import is clean after first-import CSV translation generation.
`python3 -m pip_audit -r requirements-dev.txt` reports no known vulnerabilities.

Native Compatibility renderer on Apple M4 Pro retains Slash mark, Bolt impact and
Freeze at640x360,1280x720,2560x1080. Nonblank pixel criteria and visual inspection
pass all nine captures in `build/visual-evidence/time-auxiliary/`. Boss and Player
remain visible and the temporal mark and fields retain their authored positions.

## Reversible Decisions And Limits

Bolt0.70slow is a conservative authored value for the otherwise unspecified slow
multiplier. Collapse preserves canonical three circles; existing timeline echo
final explosions retain their independent35frame warnings. No extra summon recipe
is invented. This milestone verifies these auxiliary mechanisms and regressions;
complete product gameplay, coverage, packaging and external player evidence remain
separate certification work.
