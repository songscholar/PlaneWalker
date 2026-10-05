# Registry Template Closure And Complete Content Counts

- Status: Focused Verified / Combined certification pending
- Document Role: Current focused implementation evidence
- Authority Level: Below the approved full-product completion specification
- Applies To: Launch encounter template closure, required-pack rollback and exact Base Pack counts
- Owner: Plane Walker integration team
- Last Verified: 2026-10-06
- Depends On: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`

## Baseline Failure

The clean detached `c1a24d4` validation passed both imports, Python contracts and
the 30-seed deterministic domain checks. Its full scene suite exposed the
Registry activation fixture's stale total of 446 instead of the current 448.
The two additional definitions are the retained Launch encounter extensions.

That test also exposed a runtime defect. The primary encounter profile's
template reference check was indented below `break`, inside the branch for an
already detected error. It never ran. A required composite pack containing an
otherwise valid `room_combat_missing` reference incorrectly activated all 431
definitions instead of exposing zero definitions. This is a genuine reference
validation failure, separate from the outdated test totals.

The failing immutable baseline is retained under
`build/retained-checkout/certify-c1a24d4/build/clean-validation/scene-tests/`.
The resolver's separate RED is retained under
`build/test-evidence/registry-capacity-extensions-red/`.

## Repair And Verification

The template check now executes for every primary profile recipe and preserves
the existing first-error and rollback behavior. Tests reject missing templates
in both the first and final recipe, reject missing extension templates, and
verify that a valid 433-definition composite including both extensions reaches
the same validation. The historical 431-definition composite remains valid.

Current Base Pack checks require all 448 definitions, including exactly two
encounter extensions and fifteen free cosmetics. The resolver classifies the
two extension records as specialized content: 152 generic plus 296 specialized
definitions. It requires 28 content sources, two localization sources, 67
assets and 97 integrity entries. Optional malformed content still isolates
only its own pack and preserves the complete Base Pack.

- Registry activation GREEN: 1/1, `build/test-evidence/registry-capacity-extensions-final-green/`.
- Resolver GREEN: 1/1, `build/test-evidence/registry-capacity-resolver-final-green/`.
- Complete content schema scenes GREEN: 14/14, `build/test-evidence/registry-template-content-schema-green/`.
- Dependency audit: all three pinned requirement files, no known vulnerabilities; `build/registry-capacity-extensions-dependency-audit.stdout.log`.

Both stdout and independent engine logs pass the strict scene runner. These
focused results do not certify the complete scene suite, line coverage,
five-floor combat or release packages. The failing baseline remains immutable;
combined certification must use a new committed checkout containing this fix.
