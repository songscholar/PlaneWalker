from __future__ import annotations

import hashlib
import io
import sys
import tempfile
import threading
import unittest
import zipfile
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools" / "export"))
import fetch_templates


def fixture_archive() -> bytes:
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w") as archive:
        for name in fetch_templates.TEMPLATE_FILES:
            archive.writestr("templates/" + name, "4.6.1.stable" if name == "version.txt" else bytes(range(256)) * 32)
        archive.writestr("templates/ignored_android.apk", b"unused")
    return stream.getvalue()


@contextmanager
def fixture_server(payload: bytes, wrong_range: bool = False):
    requests: list[str] = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            request = self.headers.get("Range", "")
            requests.append(request)
            start, end = (int(part) for part in request.removeprefix("bytes=").split("-"))
            body = payload[start:end + 1]
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {start + int(wrong_range)}-{end}/{len(payload)}")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}/templates.tpz", requests
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


class FetchTemplatesTest(unittest.TestCase):
    def test_range_download_verifies_archive_and_only_extracts_selected_templates(self):
        payload = fixture_archive()
        with tempfile.TemporaryDirectory() as directory, fixture_server(payload) as (url, requests):
            root = Path(directory)
            archive = fetch_templates.download_archive(url, len(payload), hashlib.sha256(payload).hexdigest(), root / "cache", workers=3, chunk_size=4096)
            output = root / "4.6.1.stable"
            fetch_templates.install_templates(archive, output)
            self.assertEqual(sorted(path.name for path in output.iterdir()), sorted(fetch_templates.TEMPLATE_FILES))
            self.assertEqual((output / "version.txt").read_text(), "4.6.1.stable")
            self.assertGreater(len(requests), 1)
            previous = len(requests)
            self.assertEqual(fetch_templates.download_archive(url, len(payload), hashlib.sha256(payload).hexdigest(), root / "cache", workers=3, chunk_size=4096), archive)
            self.assertEqual(len(requests), previous)

    def test_rejected_http_range_is_never_promoted(self):
        payload = fixture_archive()
        with tempfile.TemporaryDirectory() as directory, fixture_server(payload, wrong_range=True) as (url, _requests):
            root = Path(directory)
            with self.assertRaisesRegex(ValueError, "range"):
                fetch_templates.download_archive(url, len(payload), hashlib.sha256(payload).hexdigest(), root / "cache", workers=2, chunk_size=4096)
            self.assertFalse((root / "cache" / "templates.tpz").exists())

    def test_wrong_official_digest_cannot_install_a_download(self):
        payload = fixture_archive()
        with tempfile.TemporaryDirectory() as directory, fixture_server(payload) as (url, _requests):
            root = Path(directory)
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                fetch_templates.download_archive(url, len(payload), "0" * 64, root / "cache", workers=2, chunk_size=4096)
            self.assertFalse((root / "cache" / "templates.tpz").exists())

    def test_incomplete_download_resumes_completed_ranges(self):
        payload = fixture_archive()
        with tempfile.TemporaryDirectory() as directory, fixture_server(payload) as (url, requests):
            cache = Path(directory) / "cache"
            cache.mkdir()
            (cache / "part-000000").write_bytes(payload[:4096])
            (cache / "part-000001").write_bytes(payload[4096:5000])
            result = fetch_templates.download_archive(url, len(payload), hashlib.sha256(payload).hexdigest(), cache, workers=2, chunk_size=4096)
            self.assertEqual(result.read_bytes(), payload)
            self.assertNotIn("bytes=0-4095", requests)
            self.assertIn("bytes=5000-8191", requests)

    def test_existing_templates_are_preserved_until_a_complete_install_is_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "4.6.1.stable"
            output.mkdir()
            (output / "sentinel").write_text("preserved")
            archive = root / "incomplete.tpz"
            with zipfile.ZipFile(archive, "w") as fixture:
                fixture.writestr("templates/version.txt", "4.6.1.stable")
            with self.assertRaisesRegex(ValueError, "template"):
                fetch_templates.install_templates(archive, output)
            self.assertEqual((output / "sentinel").read_text(), "preserved")

    def test_archive_path_traversal_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "unsafe.tpz"
            with zipfile.ZipFile(archive, "w") as fixture:
                fixture.writestr("../outside", b"unsafe")
            with self.assertRaisesRegex(ValueError, "path"):
                fetch_templates.install_templates(archive, root / "templates")
            self.assertFalse((root / "outside").exists())


if __name__ == "__main__":
    unittest.main()
