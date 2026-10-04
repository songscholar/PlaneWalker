# P16P Native Training Flow

- Status: Approved / Current
- Document Role: Current focused training specification under standing project authorization
- Authority Level: Native training below the approved P16 Hub and progression design
- Applies To: TrainingRuntime, NativeTrainingFlow and physical Profile training observations
- Owner: Project training implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`
- Last Verified: 2026-10-05
- Implementation Status: Native sandbox and authenticated rewards verified; arena, UI and Boss drill follow

Training creates an independent actual Player scene configured from the active
Registry's five Launch character and five weapon profiles. All six legal time
pairs are available without purchasing or unlocking sandbox loadouts. Its
deterministic seed identifies the attempt. No launch receipt, RunState,
settlement, kill statistic or progression unlock is created by practice.

TrainingRuntime binds that exact Player and its WorldPayloadAuthority child,
the native full-player identity and successful-frame clock. It derives movement
from both committed input and displacement and semantic actions from accepted
arbitration. A primary action must leave HOLD on its real press or release;
an unreleased HOLD cannot complete a drill. The attempt's exact task/run ID
and actual native loadout seed must match the issued configuration. Pause,
death, rejected frames, duplicate signals, clock
rollback, detached/replaced native participants and foreign receipts do not
advance objectives. It exposes only sealed FIFO observations from those frames.

ProfileRuntimeService issues the adapter and derives a new training session
sequence from its durable tutorial watermark. Only that adapter may submit
an observation. TutorialRuntime consumes the selected authored task only;
training cannot accidentally reward a second task with the same input. Progress
and the first-completion reward become observable after primary-file promotion.
Save failure preserves the sealed observation for retry. Native drift during
or after saved publication stops publication and requires an explicit new
training binding; durable completed claims cannot be granted again.

NativeTrainingFlow configures the sandbox Player, binds the Profile adapter,
drains observations, and retires the Player/World subtree on close. Reset first
drains any pending save, then creates a fresh native attempt with full HP,
energy, ammo, mana and empty owned payloads. It preserves durable training
progress and completed claims. Failed writes keep the original attempt intact.

T-01, T-02, T-03, T-04 and T-06 use actual successful movement, dash, primary,
time-slot and skill actions. T-05 remains explicitly unavailable until P15
provides a reusable actual Boss conversion drill; it has no synthetic receipt
or input-signal substitute. Complete Boss drill content and Main's training
panel routing are separate integration gates.

Alternatives considered were public receipt submission and reusing the active
launch Player. The service-issued native adapter fits the existing onboarding
contract and gives a bounded observation queue plus a physical save boundary;
the independent scene keeps training lifecycle separate from launch ownership.

Completion of this slice requires actual five-weapon action frames, all 150
sandbox loadouts, physical save failure/retry, selected-task rewards, duplicate
rewards after reset/restart, dead-player reset, stale World/Player refusal and
scanned engine logs. No formal GDScript line coverage is claimed.
