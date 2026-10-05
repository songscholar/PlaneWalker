extends SceneTree

const Descriptor := preload("res://scripts/content/content_pack_descriptor.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Ledger := preload("res://scripts/save/actual_content_compatibility_ledger.gd")
const PACK := "data/content_packs/base/pack.json"
const LEDGER := "data/save/compatibility/actual_content_ledger.json"
const PROOF := "data/save/compatibility/base_p23_before_cosmetics.json"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Usage: godot --headless --path . --script tools/save/retain_p23_cosmetic_binding.gd -- SOURCE_COMMIT TARGET_COMMIT")
		quit(1)
		return
	var source_commit := _resolve(args[0])
	var target_commit := _resolve(args[1])
	var source_bytes := _read_commit(source_commit, PACK)
	var target_bytes := _read_commit(target_commit, PACK)
	var source: Variant = JSON.parse_string(source_bytes)
	var target: Variant = JSON.parse_string(target_bytes)
	var value: Variant = JSON.parse_string(_read_commit(source_commit, LEDGER))
	if source_commit.is_empty() or target_commit.is_empty() or not source is Dictionary or not target is Dictionary or not value is Dictionary or target_bytes != FileAccess.get_file_as_string("res://" + PACK) or not Ledger._reviewed_changes_only(source, target, [], Ledger.COSMETIC_FILES):
		push_error("Committed descriptors do not prove the exact additive cosmetic transition")
		quit(1)
		return
	var previous: Dictionary = value.bindings[-1]
	if previous.id != "p20_build_sharing" or not Ledger._normalize_binding(previous.snapshot) == _snapshot(source):
		push_error("Source commit does not authenticate the prior ledger target: " + JSON.stringify(_snapshot(source)))
		quit(1)
		return
	previous.descriptor_path = "res://" + PROOF
	previous.source_commits = [source_commit]
	# Earlier commits share this descriptor but did not retain every declared moth asset.
	value.bindings[0].source_commits = ["c48116a29ce8cd6752e49d0029d44b3aa528bc14"]
	value.bindings.append({"id": "p23_cosmetics", "descriptor_path": "res://" + PACK, "source_commits": [target_commit], "snapshot": _snapshot(target)})
	for edge: Dictionary in value.transitions:
		edge.target_id = "p23_cosmetics"
		edge.allowed_added_files = Ledger.COSMETIC_FILES.duplicate()
		edge.reason += " The exact twenty cosmetic resources are additive and a missing collection preserves original appearance."
	value.transitions.append({"source_id": "p20_build_sharing", "target_id": "p23_cosmetics", "allowed_changed_files": [], "allowed_added_files": Ledger.COSMETIC_FILES.duplicate(), "reason": "Reviewed fifteen free original raster appearances, their catalog, supplemental localization and provenance only. Existing authored content, Meta catalog and all required Profile v4 fields remain unchanged. Active native checkpoints retain their explicit reconstruction gate."})
	if not _write(PROOF, source_bytes) or not _write(LEDGER, JSON.stringify(value, "  ", false, true) + "\n"):
		quit(1)
		return
	print("LEDGER_SHA256=" + FileAccess.get_sha256("res://" + LEDGER))
	print("TARGET_BINDING=" + JSON.stringify(_snapshot(target)))
	quit(0)


func _snapshot(descriptor: Dictionary) -> Dictionary:
	var packs := [{"pack_id": descriptor.pack_id, "pack_version": descriptor.pack_version, "schema_version": int(descriptor.schema_version), "fingerprint_sha256": Descriptor.canonical_digest(descriptor)}]
	return {"aggregate_sha256": Envelope.content_snapshot_digest(packs), "packs": packs}


func _resolve(ref: String) -> String:
	var output: Array = []
	if OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "--verify", ref + "^{commit}"], output, true) != 0:
		return ""
	var value := str(output[0]).strip_edges()
	return value if value.length() == 40 and value.is_valid_hex_number(false) else ""


func _read_commit(commit: String, path: String) -> String:
	var output: Array = []
	if commit.is_empty() or OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "show", commit + ":" + path], output, true) != 0:
		return ""
	return str(output[0])


func _write(path: String, contents: String) -> bool:
	var file := FileAccess.open("res://" + path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot retain proof: " + path)
		return false
	file.store_string(contents)
	file.close()
	return true
