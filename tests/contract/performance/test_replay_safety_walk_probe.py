from pathlib import Path
import tempfile
import unittest

from tools.p15.replay_safety_walk_probe import instrument_source, prepare_output


class ReplaySafetyWalkProbeTests(unittest.TestCase):
    def probe(self, source):
        with tempfile.TemporaryDirectory() as directory:
            return instrument_source(source, Path(directory))

    def test_actual_root_calls_are_counted_and_recursion_keeps_original_function(self):
        source = "class_name Example\nextends RefCounted\nstatic func validate(value: Variant) -> bool:\n\treturn replay_value_is_safe(value)\nstatic func replay_value_is_safe(value: Variant) -> bool:\n\treturn replay_value_is_safe(value[0])\n"
        result = self.probe(source)
        self.assertEqual(result["rooted_calls"], [{"function": "validate", "line": 4}])
        self.assertIn("return _pw_counted_replay_value_is_safe(value)", result["source"])
        self.assertIn("return replay_value_is_safe(value[0])", result["source"])
        self.assertNotIn("class_name Example", result["source"])

    def test_member_with_same_name_is_not_counted_as_recorder_root(self):
        source = "extends RefCounted\nstatic func validate(value: Variant) -> bool:\n\tvar other := value.replay_value_is_safe(value)\n\treturn replay_value_is_safe(value)\nstatic func replay_value_is_safe(value: Variant) -> bool:\n\treturn true\n"
        result = self.probe(source)
        self.assertEqual(len(result["rooted_calls"]), 1)
        self.assertIn("value.replay_value_is_safe(value)", result["source"])

    def test_missing_original_function_and_already_instrumented_sources_fail_closed(self):
        with self.assertRaisesRegex(ValueError, "one actual"):
            self.probe("extends RefCounted\nstatic func validate(value: Variant) -> bool:\n\treturn true\n")
        with self.assertRaisesRegex(ValueError, "reserved"):
            self.probe("extends RefCounted\nstatic var __pw_diagnostic = 0\nstatic func replay_value_is_safe(value: Variant) -> bool:\n\treturn true\n")

    def test_output_requires_new_path_and_preserves_existing_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            output = root / "build" / "fresh"
            self.assertEqual(prepare_output(output, root), output)
            evidence = output / "evidence.json"
            evidence.write_text("retained", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "already exists"):
                prepare_output(output, root)
            self.assertEqual(evidence.read_text(encoding="utf-8"), "retained")
            empty = root / "build" / "empty"
            empty.mkdir()
            with self.assertRaisesRegex(ValueError, "already exists"):
                prepare_output(empty, root)

    def test_output_refuses_symlink_ancestors_and_paths_outside_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            actual = root / "build" / "actual"
            actual.mkdir(parents=True)
            alias = root / "build" / "alias"
            alias.symlink_to(actual, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "symlink"):
                prepare_output(alias / "fresh", root)
            with self.assertRaisesRegex(ValueError, "inside workspace build"):
                prepare_output(root / "outside", root)


if __name__ == "__main__":
    unittest.main()
