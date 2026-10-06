extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Runner := preload("res://tests/support/p15_native_boss_matrix_runner.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")


func _ready() -> void:
	var suite := Suite.new()
	var previous := OS.get_environment("PLANEWALKER_MATRIX_PARTIAL_OUTPUT")
	var directory := "user://native-matrix-persistence-%d" % Time.get_ticks_usec()
	var partial := directory.path_join("partial.json")
	OS.set_environment("PLANEWALKER_MATRIX_PARTIAL_OUTPUT", partial)
	var source := {"runtime_source_sha256": "a".repeat(64), "revision": "b".repeat(40), "instrumented": false}
	var binding := {"aggregate_sha256": "c".repeat(64), "packs": [{"pack_id": "base", "pack_version": "test", "schema_version": 2, "fingerprint_sha256": "d".repeat(64)}]}
	var clock := {"physics_ticks_per_second": 60, "time_scale": 1.0}
	var runner := Runner.new()
	runner._source = source
	runner._binding = binding
	suite.assert_true(runner._persist_partial(0, 2, clock), "matrix persists empty incomplete identity before its first case")
	var empty: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(partial))
	suite.assert_true(empty.partial and not empty.complete and empty.production_case_count == 0, "empty partial cannot claim completion")
	var row := {"identity": Runner._identity(0), "failures": [], "frames": 7, "trace": [{"phase": 1, "amount": 0.3}], "tags": PackedStringArray(["native"])}
	suite.assert_true(runner._persist_case(row, 0, 2, clock), "case receipt and manifest atomically persist full typed data")
	var restored := Runner.new()
	restored._source = source
	restored._binding = binding
	var rows: Array[Dictionary] = []
	suite.assert_true(restored._load_resume(partial, 0, 2, 1, rows), "fresh runner loads exactly one committed typed receipt")
	suite.assert_equal(rows, [row], "native integer and packed-array types survive fresh recovery")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(partial))
	var receipt_path := directory.path_join("cases/case-000000.json")
	var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	var forged := row.duplicate(true)
	forged.frames = 8
	receipt.typed_row = Replay.encode_replay_json({"row": forged}).json
	suite.assert_true(Runner._write_atomic(receipt_path, receipt), "tamper fixture updates only typed payload")
	manifest.case_receipts[0].sha256 = FileAccess.get_file_as_string(receipt_path).sha256_text()
	suite.assert_true(Runner._write_atomic(partial, manifest), "tamper fixture authenticates outer bytes")
	var rejected: Array[Dictionary] = []
	suite.assert_true(not restored._load_resume(partial, 0, 2, 1, rejected), "recomputed receipt hashes cannot hide typed/JSON disagreement")
	var orphan_runner := Runner.new()
	orphan_runner._source = source
	orphan_runner._binding = binding
	var orphan_path := receipt_path + ".orphan." + FileAccess.get_file_as_string(receipt_path).sha256_text()
	suite.assert_true(orphan_runner._persist_case(row, 0, 2, clock), "uncommitted receipt is retained and replaced only by real reexecution")
	suite.assert_true(FileAccess.file_exists(orphan_path), "orphan bytes remain reviewable after crash recovery")
	OS.set_environment("PLANEWALKER_MATRIX_PARTIAL_OUTPUT", previous)
	suite.finish(get_tree())
