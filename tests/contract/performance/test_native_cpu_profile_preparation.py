import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("native_cpu_prepare", ROOT / "tools/p15/prepare_native_cpu_profile.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class NativeCpuProfilePreparationTest(unittest.TestCase):
    def test_original_control_flow_is_preserved_and_typed_wrapper_forwards_defaults(self):
        source = "class_name Fixture\nextends Node\n\nfunc observe(kind: String, frame: int = -1) -> Dictionary:\n\tif frame < 0:\n\t\treturn {}\n\treturn {\"kind\": kind, \"frame\": frame}\n"
        value = MODULE.instrument(source, "scripts/fixture.gd", [("observe", "kind: String, frame: int = -1", "kind, frame", "Dictionary")])
        original_body = source.split(" -> Dictionary:\n", 1)[1]
        self.assertIn("extends Node\nconst _NativeCpuProfile", value)
        self.assertIn("func _native_cpu_impl_observe(kind: String, frame: int = -1) -> Dictionary:\n" + original_body, value)
        self.assertIn("return _native_cpu_impl_observe(kind, frame)", value)
        self.assertIn("var value: Dictionary = _native_cpu_impl_observe(kind, frame)", value)

    def test_void_wrapper_preserves_fast_return_and_measured_call(self):
        value = MODULE.instrument("extends Node\nfunc update() -> void:\n\tpass\n", "scripts/fixture.gd", [("update", "", "", "void")])
        self.assertIn("_native_cpu_impl_update()\n\t\treturn", value)
        self.assertIn("_native_cpu_impl_update()\n\t_NativeCpuProfile.leave(started)", value)

    def test_duplicate_or_wrong_typed_methods_and_repeated_instrumentation_refuse(self):
        methods = [("observe", "", "", "Dictionary")]
        for source in ["extends Node\nfunc observe() -> bool:\n\treturn true\n", "extends Node\nfunc observe() -> Dictionary:\n\treturn {}\nfunc observe() -> Dictionary:\n\treturn {}\n", "extends Node\nconst _NativeCpuProfile = 1\n"]:
            with self.subTest(source=source), self.assertRaises(ValueError):
                MODULE.instrument(source, "scripts/fixture.gd", methods)


if __name__ == "__main__":
    unittest.main()
