from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PROJECT_ROOT / "tools/export"))

from portable_runtime import (  # noqa: E402
    REGISTERED_CA_CALLSITE,
    REGISTERED_CA_LINE,
    build_portable_fallback,
    classified_log_failures,
    prepare_self_contained_editor,
    project_build_path,
)


class PortableRuntimeBoundaryTest(unittest.TestCase):
    def test_output_cannot_escape_project_or_replace_build_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            for path in (root.parent / "outside", root / "build", Path("build/../../outside")):
                with self.subTest(path=path), self.assertRaises(ValueError):
                    project_build_path(root, path)

    def test_untrusted_runtime_rejected_before_execution_or_copy(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            source = root / "untrusted"
            source.write_text("not executable", encoding="utf-8")
            manifest = root / "data/toolchain/m1_godot_toolchains.json"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps({"toolchains": [{"sha256": "0" * 64}]}), encoding="utf-8")
            report, code = build_portable_fallback(root, source, Path("build/package"), Path("build/evidence.json"))
            self.assertEqual(code, 4)
            self.assertIn("allowlist", report["issues"][0]["message"])
            self.assertFalse((root / "build/package/Godot").exists())
            self.assertEqual(report["steps"], [])

    def test_modified_cached_editor_is_not_executed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            source = root / "source"
            source.write_bytes(b"verified source")
            editor = prepare_self_contained_editor(root, source)
            editor.write_bytes(b"modified cache")
            with self.assertRaisesRegex(ValueError, "differs"):
                prepare_self_contained_editor(root, source)

    def test_only_registered_ca_error_with_its_callsite_is_environmental(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / "engine.log"
            log.write_text(REGISTERED_CA_LINE + "\n   " + REGISTERED_CA_CALLSITE + "526)\nSCRIPT ERROR: broken\n", encoding="utf-8")
            failures, environmental = classified_log_failures([log])
            self.assertEqual([entry["code"] for entry in failures], ["script_error"])
            self.assertEqual(len(environmental), 1)
            log.write_text(REGISTERED_CA_LINE + "\n   at: other_function (other.cpp:1)\n", encoding="utf-8")
            failures, environmental = classified_log_failures([log])
            self.assertEqual([entry["code"] for entry in failures], ["engine_error"])
            self.assertEqual(environmental, [])


if __name__ == "__main__":
    unittest.main()
