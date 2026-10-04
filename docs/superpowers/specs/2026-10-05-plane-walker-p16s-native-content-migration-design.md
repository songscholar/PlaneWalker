# P16S Trusted Active Content Migration Specification

- Status: Approved / Current
- Document Role: Current active/native Profile content compatibility authority
- Authority Level: Production migration below standing project authorization
- Applies To: GameState activation, Profile authentication and atomic Save rebinding
- Owner: Project runtime implementation lead
- Depends On: `AGENTS.md`, `2026-10-05-plane-walker-p16r-native-combat-checkpoint-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Trusted compatible native migration and incompatible refusal pass

Only the exact source/target transitions authenticated by the content ledger may
migrate active Profiles. The migration retains the whole payload unchanged and
uses the existing SaveService compare-and-swap rebind transaction. It cannot
mint currency, launch another Run, increment Profile revision or settle a Run.

Completion criteria:

1. Every trusted source accepts canonical compatible active Run state after
   actual current Facade restoration and exact domain comparison.
2. A native checkpoint must additionally pass Profile/settlement authentication
   and production Host restoration in an invisible, disabled native probe.
3. The probe restores actual Player, authored room, Actors and effects and is
   synchronously retired before any envelope promotion. It never advances a
   gameplay frame or publishes spawn/settlement events.
4. Physical reopened migrated native Profiles continue their saved frame through
   production Main. Terminal settled checkpoint lineage remains unchanged.
5. Unknown content, corrupt/re-signed state and incompatible authored native
   definitions refuse migration without changing primary bytes or memory.
6. Repeated activation is idempotent; the entire extension payload and original
   checkpoint digest survive the atomic rebind. Save promotion failures retain
   existing SaveService compensation behavior.

Historical-binding fixtures use canonical current runtime state to establish
compatibility, not to claim recovery of undocumented legacy combat formats.
An older incompatible Actor/effect definition remains explicitly refused until
an authenticated format-specific converter exists.
