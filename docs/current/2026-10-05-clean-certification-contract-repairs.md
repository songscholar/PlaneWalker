# Clean Certification Contract Repairs

- Status: Focused Verified / Combined certification pending
- Document Role: Current retention evidence
- Authority Level: Evidence below approved full-product design
- Applies To: Base content registration and native Host fixture contract
- Owner: Plane Walker implementation team
- Last Verified: 2026-10-05
- Depends On: [full product completion design](../superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md)

## Retained Changes

The detached `5eb4149edb95a30c8c26d86d480e4b8dc6b8b02d` checkout exposed two
outdated content totals. The actual base pack includes fifteen free cosmetics,
so its authoritative current total is446. Category checks now explicitly require
all fifteen cosmetics, preserve the M1 boundary and verify optional-pack isolation.
The historical P16-only composite fixture still contains431 records.

The same clean suite exposed the Event Host fixture's missing native driver.
Production Host requires its driver to bind the profile launch receipt resolver.
The test Runner now owns a driver fixture implementing that exact contract, and
asserts the resolver is bound. Production validation still rejects a missing
driver. Host failures include their actual code and context in test diagnostics.

## Executable Evidence

- RED: detached source logs under `build/certified/5eb4149-source/build/evidence/attempt-2/logs`.
- Content schema GREEN: `build/test-evidence/content-count-repair`,14/14 scenes.
- Event contract diagnostic RED: `build/test-evidence/event-facade-diagnostic`,native driver missing.
- Event Host GREEN: `build/test-evidence/event-facade-final-green`,1/1,clean engine log.
- Dependency audit: `python3 -m pip_audit -r requirements-dev.txt -r requirements-coverage.txt -r requirements-production-art.txt --progress-spinner off`,no known vulnerabilities.

These focused repairs are not whole-release certification. The retained detached
checkout intentionally excludes later native mechanisms; rerun validation,
instrumented coverage, exports and packaged startup from a new committed source.
Use the configured Python3.10 binary in `PATH` and the workspace coverage virtual
environment explicitly. The first attempt recorded a missing-jsonschema failure
when the shell selected a different Python interpreter.
