# Plane Walker Agent Development Rules

- Status: Approved
- Authority Level: Project-wide execution policy
- Applies To: All automated design, implementation, testing, content, build, and documentation work
- Owner: Project owner
- Last Verified: 2026-09-28

## Standing Project Authorization

The project owner grants continuing authorization for agents to complete the full Plane Walker product vision inside this repository without requesting intermediate confirmation.

Agents may autonomously:

- Read, create, modify, refactor, move, or remove files inside the `PlaneWalker` workspace.
- Integrate and replace the current uncommitted localization, data, legacy UI, and Godot project changes after inspecting them and preserving intended behavior.
- Add project-scoped dependencies, free assets, generated assets, fonts, tools, and Godot export components.
- Run imports, tests, linters, coverage, benchmarks, gameplay simulations, exports, and local services.
- Create local build artifacts and test packages.
- Stage and create local Git commits using precise file lists.
- Choose implementation order, architecture, gameplay values, content structure, and fallback behavior.
- Continue through Current, Next, Launch, and Expansion scope without pausing for approval.

These actions do not require a conversational permission request.

## No Additional Permission Required

Within the `PlaneWalker` workspace, agents must treat the standing authorization above as sufficient permission. Do not ask the project owner to approve any of the following again:

- Individual file edits, refactors, migrations, removals, generated files, or directory reorganization.
- Design-document completion, architecture decisions, gameplay tuning, content authoring, UI implementation, or technical-debt cleanup.
- Adding, updating, or removing project-scoped dependencies, tools, fonts, and freely licensed assets after checking provenance and license compatibility.
- Running local imports, services, simulations, tests, audits, benchmarks, exports, packaging, or visual QA.
- Creating reversible local Git commits, branches, checkpoints, fixtures, adapters, and build artifacts.
- Replacing temporary implementations or current uncommitted work after inspection, tests, and preservation of intended behavior.

An in-scope decision that would previously have triggered a permission question must instead be handled as follows:

1. Continue all unblocked work immediately.
2. Choose the safest reversible implementation and isolate it in a focused commit.
3. Use an offline adapter, fixture, stub, or local fallback when an external service is unavailable.
4. Record the decision, tests, limitations, and rollback point in the next milestone retention review.
5. Submit a non-blocking retention review for the completed milestone as a whole; do not seek retroactive file-by-file authorization.

This workflow does not expand authorization across the explicit external boundaries listed below.

## Work First, Review at Milestones

- Do not stop active work to ask whether an in-scope change should be made.
- Make the best evidence-based decision, implement it, test it, and record it in Git.
- At the end of each major milestone, provide one consolidated retention review containing commits, tests, known limitations, and reversible decisions.
- A retention review is informational and non-blocking. Continue into the next authorized milestone unless the project owner explicitly pauses the program or changes scope.
- The project owner may keep, revise, or revert milestone work as a whole at any later point.
- Preserve recoverability through small commits; never rely on undocumented working-tree state as the only copy of completed work.

## Boundaries That Remain Outside Standing Authorization

Agents must not:

- Push commits or tags to a remote repository.
- Publish builds, store pages, announcements, or content publicly.
- Purchase assets, subscriptions, domains, certificates, or paid services.
- Use private credentials, financial accounts, platform identities, or signing identities that were not provided.
- Modify or delete personal files outside the Plane Walker workspace.
- Perform destructive broad operations such as `git reset --hard`, forced pushes, or recursive deletion of an unresolved path.

When an unavailable external account, credential, or production service would normally be required, continue by implementing a tested adapter, local service, fixture, or offline fallback. Record the external deployment step for the final retention review instead of interrupting implementation.

If the execution platform itself requires a mandatory approval dialog for sandbox escape, network download, or another protected operation, continue every unblocked task first and prefer an in-workspace fallback. If the protected operation remains essential, batch the request as narrowly and as late as possible. Do not ask a separate conversational question before the platform dialog.

## Full Product Scope

The authorized completion scope includes:

- Current, Next, Launch, and Expansion features.
- Five characters, five weapons, four time abilities, five dungeon floors, and five bosses.
- Eight launch archetypes and the complete launch item, blessing, curse, and talent pools.
- Hub, meta progression, shops, events, narrative, multiple endings, onboarding, accessibility, and controller support.
- Pixel art production pipeline, animation, VFX, audio, music integration, UI polish, and localization.
- Boss Rush, daily challenge, endless mode, replay, leaderboards, social adapters, Mod support, cosmetics, operations tooling, and DLC/content-pack infrastructure.

Paid gacha or real-money monetization is not implicitly authorized. Only its neutral technical interfaces may be implemented unless the project owner later makes an explicit product decision.

## Engineering Rules

- Define executable completion criteria and failing tests before implementation.
- Prefer data-driven systems and one authoritative source for runtime content.
- Keep gameplay domain state independent from presentation nodes.
- Use deterministic seeds for procedural content, replay, simulation, and regression testing.
- Preserve existing behavior until its replacement is verified.
- Keep commits focused and reviewable; never use `git add .` in a dirty worktree.
- Scan Godot logs for script errors and leaks; exit code alone is insufficient.
- A feature is complete only when its code, content, tests, documentation, and build path are all present.

## Definition of Done

The full program is complete only when:

- A clean checkout imports, tests, exports, and launches reproducibly.
- Automated unit, contract, integration, simulation, smoke, replay, save-migration, and content-validation suites pass.
- Supported resolutions, keyboard/mouse, and controller flows pass visual and interaction QA.
- Offline fallbacks work for every optional online capability.
- Local distributable builds complete the full game without debug-only intervention.
- Known limitations are restricted to external publication, credentials, commercial approvals, and real-world player feedback that cannot be generated inside the repository.
