extends RefCounted

const Provider := preload("res://scripts/platform/platform_provider.gd")
const Rules := preload("res://scripts/platform/platform_rules.gd")
const Installer := preload("res://scripts/expansion/data_only_pack_installer.gd")
const Entitlements := preload("res://scripts/expansion/offline_entitlement_provider.gd")
const BuildCodec := preload("res://scripts/progression/build_share_codec.gd")
const ReplayPackage := preload("res://scripts/replay/player_replay_package.gd")
const Stream := preload("res://scripts/replay/run_replay_stream_store.gd")
const MAX_EXPORT_BYTES := 16 * 1024 * 1024
const MAX_REPLAY_EXPORT_BYTES := Stream.MAX_PACKAGE_BYTES
const MAX_TOTAL_EXPORT_BYTES := Stream.MAX_ARCHIVE_BYTES
const MAX_EXPORTS := 100
const MAX_DISCOVERY_SOURCES := 64
var _root := ""
var _export_root := ""
var _sources: Array[String] = []
var _entitlements: RefCounted = Entitlements.new()
var _binding: Dictionary = {}
var _version := ""
var _domain := ""


func configure(root: String, version: String, binding: Dictionary, domain: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(root).simplify_path()
	if not Rules.storage_path_safe(root):
		return Provider.failure(&"UNSAFE_PATH")
	_root = absolute
	_export_root = _root.path_join("exports")
	if _is_link(_export_root):
		return Provider.failure(&"UNSAFE_PATH")
	var error := DirAccess.make_dir_recursive_absolute(_export_root)
	if error != OK:
		return Provider.failure(&"IO_ERROR", {"error": error})
	_binding = binding.duplicate(true)
	_version = version
	_domain = domain
	_entitlements.configure([], [])
	return Provider.success()


func configure_local_content(sources: Array, entries: Array, owned_tags: Array) -> Dictionary:
	if _root.is_empty() or sources.size() > MAX_DISCOVERY_SOURCES or entries.size() > 256 or owned_tags.size() > 256:
		return Provider.failure(&"INVALID_ARGUMENT")
	var paths: Array[String] = []
	for source: Variant in sources:
		if not _allowed_source(source) or paths.has(ProjectSettings.globalize_path(source).simplify_path()):
			return Provider.failure(&"UNSAFE_PATH")
		paths.append(ProjectSettings.globalize_path(source).simplify_path())
	for entry: Variant in entries:
		if not entry is Dictionary or not _allowed_source(entry.get("local_source_path")):
			return Provider.failure(&"UNSAFE_PATH")
	var entitlement := Entitlements.new()
	var configured := entitlement.configure(entries, owned_tags)
	if not configured.ok:
		return Provider.failure(configured.code, configured.context)
	paths.sort()
	_sources = paths
	_entitlements = entitlement
	return Provider.success()


func entitlements() -> Dictionary:
	return Provider.success(_entitlements.snapshot())


func discover_content() -> Dictionary:
	var rows: Array[Dictionary] = []
	var diagnostics: Array[Dictionary] = []
	var installer := Installer.new()
	var seen: Dictionary = {}
	for source: String in _sources:
		if not _allowed_source(source):
			diagnostics.append({"path": source, "code": "UNSAFE_PATH"})
			continue
		var inspected := installer.inspect(source)
		if not inspected.ok:
			diagnostics.append({"path": source, "code": str(inspected.code)})
			continue
		var descriptor: Dictionary = inspected.context.descriptor
		if seen.has(descriptor.pack_id):
			diagnostics.append({"path": source, "code": "DUPLICATE_PACK_ID"})
			continue
		seen[descriptor.pack_id] = true
		rows.append({"pack_id": descriptor.pack_id, "pack_version": descriptor.pack_version, "fingerprint_sha256": descriptor.fingerprint_sha256, "local_source_path": source, "entitlement_tag": descriptor.entitlement_tag})
	rows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return left.pack_id < right.pack_id)
	return Provider.success({"entries": rows, "diagnostics": diagnostics, "supports_download": false})


func share_build(build: Dictionary) -> Dictionary:
	var encoded := BuildCodec.encode(build)
	if not encoded.ok:
		return Provider.failure(encoded.code)
	var exported := _export(str(encoded.context.share_code).to_utf8_buffer(), "txt", "build")
	if exported.ok:
		exported.context["share_code"] = encoded.context.share_code
	return exported


func share_replay(package: Dictionary) -> Dictionary:
	var bytes := JSON.stringify(package, "", true, true).to_utf8_buffer()
	if bytes.size() > MAX_REPLAY_EXPORT_BYTES:
		return Provider.failure(&"ARTIFACT_CAPACITY")
	var validated: Dictionary
	if package.get("schema_id") == "planewalker.run_replay_package":
		var validator := Stream.new()
		if not validator.has_method("validate_package"):
			return Provider.failure(&"REPLAY_FORMAT_UNAVAILABLE")
		validated = validator.call("validate_package", package, _version, _binding)
	else:
		validated = ReplayPackage.validate(package, _version, _binding, _domain)
	if not validated.ok:
		return Provider.failure(validated.code)
	return _export(JSON.stringify(validated.context.package, "", true, true).to_utf8_buffer(), "json", "replay")


func capture_screenshot(image: Image) -> Dictionary:
	var copied: Image = image.duplicate()
	if copied.is_compressed():
		if copied.decompress() != OK:
			return Provider.failure(&"INVALID_ARGUMENT")
	copied.convert(Image.FORMAT_RGBA8)
	return _export(copied.save_png_to_buffer(), "png", "screenshot")


func share_cloud(key: String, entry: Dictionary) -> Dictionary:
	var envelope := {"schema_id": "planewalker.local_cloud_export", "schema_version": 1, "key": key, "entry": entry.duplicate(true), "content_snapshot": _binding.duplicate(true), "save_domain": _domain, "game_version": _version}
	return _export(JSON.stringify(envelope, "", true, true).to_utf8_buffer(), "json", "profile")


func _export(bytes: PackedByteArray, extension: String, kind: String) -> Dictionary:
	if not Rules.storage_path_safe(_export_root):
		return Provider.failure(&"UNSAFE_PATH")
	var limit := MAX_REPLAY_EXPORT_BYTES if kind == "replay" else MAX_EXPORT_BYTES
	if bytes.is_empty() or bytes.size() > limit:
		return Provider.failure(&"ARTIFACT_CAPACITY")
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var digest := hash.finish().hex_encode()
	var path := _export_root.path_join("%s_%s.%s" % [kind, digest, extension])
	var pending := path + ".pending"
	if _is_link(path) or _is_link(pending):
		return Provider.failure(&"UNSAFE_PATH")
	if FileAccess.file_exists(path):
		var existing := FileAccess.open(path, FileAccess.READ)
		if existing == null or existing.get_length() != bytes.size() or existing.get_buffer(existing.get_length()) != bytes:
			return Provider.failure(&"ARTIFACT_CONFLICT")
		return Provider.success({"path": path, "digest": digest, "kind": kind, "duplicate": true, "local_only": true})
	var directory := DirAccess.open(_export_root)
	if directory == null:
		return Provider.failure(&"IO_ERROR")
	var names := directory.get_files()
	if names.size() >= MAX_EXPORTS:
		return Provider.failure(&"ARTIFACT_CAPACITY")
	var total := bytes.size()
	for name: String in names:
		var file_path := _export_root.path_join(name)
		if _is_link(file_path):
			return Provider.failure(&"UNSAFE_PATH")
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			return Provider.failure(&"IO_ERROR")
		total += file.get_length()
		if total > MAX_TOTAL_EXPORT_BYTES:
			return Provider.failure(&"ARTIFACT_CAPACITY")
	var output := FileAccess.open(pending, FileAccess.WRITE)
	if output == null:
		return Provider.failure(&"IO_ERROR")
	output.store_buffer(bytes)
	output.flush()
	var error := output.get_error()
	output.close()
	if error != OK:
		return Provider.failure(&"IO_ERROR")
	var verified := FileAccess.open(pending, FileAccess.READ)
	if verified == null or verified.get_length() != bytes.size() or verified.get_buffer(verified.get_length()) != bytes:
		return Provider.failure(&"ARTIFACT_VERIFICATION_FAILED")
	verified.close()
	if _is_link(_root) or _is_link(_export_root) or _is_link(path) or _is_link(pending):
		return Provider.failure(&"UNSAFE_PATH")
	if DirAccess.rename_absolute(pending, path) != OK:
		return Provider.failure(&"IO_ERROR")
	return Provider.success({"path": path, "digest": digest, "kind": kind, "duplicate": false, "local_only": true})


func _allowed_source(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.contains("\\") or value.contains("/../") or value.ends_with("/..") or value.contains("/./"):
		return false
	var path := ProjectSettings.globalize_path(value).simplify_path()
	var workspace := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var workshop := _root.path_join("workshop")
	var base := workspace if path.begins_with(workspace + "/") else workshop
	if not path.begins_with(base + "/") or _is_link(base):
		return false
	var current := base
	for component: String in path.trim_prefix(base + "/").split("/"):
		current = current.path_join(component)
		if _is_link(current):
			return false
	return true


static func _is_link(path: String) -> bool:
	var parent := DirAccess.open(path.get_base_dir())
	return parent != null and parent.is_link(path.get_file())
