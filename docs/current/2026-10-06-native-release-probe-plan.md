# Native Release Runtime Probe Plan

- Status: Approved / Current
- Document Role: Current focused official release runtime measurement acceptance criteria
- Authority Level: Below approved full-product completion contract
- Applies To: Native Main performance probe through a packaged release executable
- Owner: Project integration lead
- Depends On: `2026-10-06-native-unified-recording-600-evidence.md`
- Last Verified: 2026-10-06

## Observed Invocation Failure

The official macOS release template executable has SHA-256
`aa1a4febbb87876717d6d2fc9b65ad0878696d1e676b64c1bb1c18775bb1f070`
and version `4.6.1.stable.official.14d19694e`. It explicitly refuses the
existing runner's `--path` argument because path overrides are disabled in
this export template. A separate actual invocation confirms `--main-pack`
is also refused before startup. The unchanged frozen `9738bc5` attempt is retained at
`build/retained-checkout/native-unified-9738bc5-20261006/build/floor4-phase2-release-parent-late-600/`.
The project never started; this is invocation evidence, not a gameplay result.

## Scoped Replacement

Add a packaged-binary mode to the existing runner. It invokes the package's
own main scene without `--path` or an explicit scene argument. Require the
packaged resource file and authenticate the macOS bundle's actual automatic
loading layout through `Info.plist` and its `CFBundleExecutable`. Refuse an
unrelated PCK, symbolic-link indirection and unsupported package layouts.
Retain the executable, resource and plist checksums, actual command, mode,
and pre/post stability. Existing source-checkout hashes
describe the measured source inputs; they alone do not authenticate code
inside a package. Retain export provenance and the package's resource hash
separately to bind that code to its source.

Use a fresh retained checkout with unchanged production scripts. Change only
its project main-scene setting to the existing performance harness. This
release probe package is a diagnostic artifact, not a playable distribution.
The production Main is still instantiated and exercised by that harness.
Do not change the game's production startup scene or historical measurements.

## Executable Acceptance

Before implementation, contract tests must fail only the missing packaged
invocation and new measurement-schema behavior. Then verify that the
package mode omits unsupported path/scene arguments, records real artifact
identities, and refuses binary/resource/source changes, timeouts and runtime
errors. Version-one and version-two report validation remains compatible and
strict.

Version-three measurements report the actual `OS.is_debug_build()` result
and an explicit static-memory-monitor availability record. An observed zero
may be unavailable only in a release build; debug zero remains invalid. A
positive observed monitor is available in either build. A valid actual
process RSS record remains mandatory. Missing memory data cannot be replaced
with an invented positive value or an estimated memory/FPS certificate.

Run the packaged release harness with the same real Sword admission,
600 consecutive late phase-two frames, declared survival/prerequisite
fixtures and fresh physical typed tape endpoints. Validate paired logs and
retain export/import diagnostics separately. Record concurrent processes.
Compare editor and release observations without attributing their difference
to a production optimization. Rendered saturation, long recording, the
45-minute soak, UI acceptance and human playtests remain separate gates.

## Runtime PID Bootstrap Acceptance

The first actual version-three release run retains correct native frames and
physical tape endpoints but fails RSS validation: stdout remains buffered until
process exit, so the previous sampler never acquires a live process identity.
Keep that failed report unchanged.

The runner supplies a new `output.parent/process.pid` path through
`PLANEWALKER_PERFORMANCE_PID_FILE`. Before content or Main is loaded, the probe
writes its actual `OS.get_process_id()`, flushes and closes this independent
file. The sampler prioritizes the file; malformed or symlinked files cannot
fall back to an apparently valid stdout identity. A preexisting bootstrap path,
including directories and dangling symlinks, refuses before any subprocess.

Version-three retention must independently read the physical bootstrap file
and final stdout, then require their identities to equal the report's native
process id and the RSS sampler's observed process id. Exactly one final stdout
announcement is required, including refusal of duplicate or malformed lines.
Retain the binding and its refusal details in `native_pid_binding`; never trust
that field as supplied by the runtime report. Versions one and two retain
their existing validation and legacy stdout fallback. Positive real RSS
samples remain mandatory for versions two and three.

Retain an empty-stdout/physical-bootstrap failing test against the preceding
committed tool before production changes. Then run both performance contract
modules, parse the GDScript through the existing pinned toolchain, and obtain
independent review. Only after the combined gameplay and probe changes are
committed may a new derived checkout be imported, exported and measured in a
fresh directory. Retain the committed source identity, disclosed main-scene
override, export logs and package hashes. Passing tool contracts alone cannot
certify release memory, frame budgets or any other gameplay gate.
