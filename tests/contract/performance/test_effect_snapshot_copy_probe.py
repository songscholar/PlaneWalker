import tempfile
from pathlib import Path
import unittest

from tools.p15.effect_snapshot_copy_probe import instrument_source


class EffectSnapshotCopyProbeTests(unittest.TestCase):
    def probe(self, source):
        with tempfile.TemporaryDirectory() as directory:
            return instrument_source(source, Path(directory))

    def test_only_actual_snapshot_deep_copy_is_instrumented(self):
        source = "class_name Example\nextends RefCounted\nfunc snapshot() -> Dictionary:\n\treturn _state.duplicate(true)\nfunc other() -> Dictionary:\n\treturn _state.duplicate(true)\n"
        result = self.probe(source)
        self.assertEqual(result["copy_calls"], [{"line": 4, "receiver": "_state", "expression": "_state.duplicate(true)"}])
        self.assertIn("return _pw_snapshot_deep_copy_probe(_state)", result["source"])
        self.assertIn("func other() -> Dictionary:\n\treturn _state.duplicate(true)", result["source"])
        self.assertNotIn("class_name Example", result["source"])

    def test_shallow_copy_keeps_original_operation(self):
        source = "extends RefCounted\nfunc snapshot() -> Dictionary:\n\tvar value := _state.duplicate()\n\treturn value.duplicate(true)\n"
        result = self.probe(source)
        self.assertIn("var value := _state.duplicate()", result["source"])
        self.assertEqual(result["copy_calls"][0]["receiver"], "value")

    def test_unobserved_deep_copy_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "no observed deep"):
            self.probe("extends RefCounted\nfunc snapshot() -> Dictionary:\n\treturn {}\n")

    def test_ambiguous_duplicate_argument_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "literal deep-copy"):
            self.probe("extends RefCounted\nfunc snapshot() -> Dictionary:\n\treturn _state.duplicate(flag)\n")

    def test_reserved_probe_identity_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "reserved snapshot"):
            self.probe("extends RefCounted\nvar _pw_snapshot_copy_inputs = []\nfunc snapshot() -> Dictionary:\n\treturn _state.duplicate(true)\n")
