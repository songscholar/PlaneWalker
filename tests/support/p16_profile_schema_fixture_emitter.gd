extends SceneTree

const CatalogFactory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Run := preload("res://scripts/application/run_state.gd")


func _initialize() -> void:
	call_deferred("_emit")


func _emit() -> void:
	var loaded: Dictionary = CatalogFactory.load_base()
	if not loaded.ok:
		_fail("CatalogFactory: %s" % loaded)
		return
	var catalog: RefCounted = loaded.context.catalog
	var state = Profile.new()
	if not state.configure(catalog):
		_fail("MetaProfileState rejected Base Pack")
		return
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save/profile_v3.json"))
	var created = Envelope.create_profile(
		legacy.profile_id, legacy.save_domain, legacy.sequence, legacy.game_version,
		legacy.created_at_utc, legacy.saved_at_utc, legacy.content_snapshot, legacy.payload, catalog
	)
	if not created.ok:
		_fail("SaveEnvelope: %s" % created.to_dictionary())
		return
	var run = Run.new()
	run.reset_domain({"milestone": "M1", "seed": 4}, "legacy-active-run")
	var active_payload: Dictionary = legacy.payload.duplicate(true)
	active_payload["active_run_state"] = run.snapshot()
	var active = Envelope.create_profile(
		legacy.profile_id, legacy.save_domain, legacy.sequence, legacy.game_version,
		legacy.created_at_utc, legacy.saved_at_utc, legacy.content_snapshot, active_payload, catalog
	)
	if not active.ok:
		_fail("SaveEnvelope active run: %s" % active.to_dictionary())
		return
	print("META_PROFILE_FIXTURE=" + JSON.stringify(state.snapshot(), "", true, true))
	print("SAVE_PROFILE_FIXTURE=" + JSON.stringify(created.payload, "", true, true))
	print("ACTIVE_SAVE_PROFILE_FIXTURE=" + JSON.stringify(active.payload, "", true, true))
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
