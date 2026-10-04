# P19 Packaged Startup Plan

- Status: Approved / Current
- Document Role: Current implementation plan
- Authority Level: Execution below full-product completion specification
- Applies To: Godot 4.6.1 release exports and host-compatible startup diagnostics
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Three real exports and authenticated host release startup pass; non-host execution is recorded separately

## Completion Contract

1. An unsupported platform is refused even when the manifest and preset agree.
2. Windows, Linux and macOS release exports produce actual authenticated artifacts.
3. The official release template launches its own configured Main from an empty
   working directory, without editor support or resource path overrides.
4. A diagnostic started with an explicit user argument requires isolated user
   data, opens all three real Hub districts, submits the real gateway command
   with a deterministic seed through the native controller,
   enters a production combat room, checks real native actors and writes a
   durable checkpoint. It exits cleanly and produces a structured result.
5. The verifier refuses changed artifacts, missing/malformed results, process
   failures, engine/script/resource errors and leaks, including zero-exit errors.
6. Host-incompatible artifacts are recorded as unexecuted. This milestone does
   not certify full-game completion, non-host startup or authentic playtests.

## Execution

- [x] Reproduce unsupported Linux/BSD admission in the real engine and contract.
- [x] Pin the Godot 4.6.1 Linux/X11 platform and run export contracts.
- [x] Export all three real targets using the official project-local templates.
- [x] Implement release-compatible Main diagnostic and verifier refusal tests.
- [x] Run the actual packaged executable and retain its startup evidence.
- [ ] Commit the focused build changes and continue combined certification.
