import contextlib
import http.server
import io
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


helper = load("netmode_root", ROOT / "root" / "netmode-root")
cli = load("netmode_cli", ROOT / "bin" / "netmode")


class ModeTable(unittest.TestCase):
    def test_overrides_only_known_keys(self):
        for mode, spec in helper.MODES.items():
            self.assertLessEqual(set(spec["sysctl"]), set(helper.BASE), mode)

    def test_every_mode_is_described(self):
        for mode, spec in helper.MODES.items():
            for field in ("name", "icon", "blurb", "wifi_awake", "sysctl"):
                self.assertIn(field, spec, mode)

    def test_blurbs_fit_the_card(self):
        for spec in helper.MODES.values():
            self.assertLessEqual(len(spec["blurb"]), 30)

    def test_list_is_json_and_needs_no_root(self):
        r = subprocess.run([sys.executable, "-I", str(ROOT / "root" / "netmode-root"), "list"],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0)
        self.assertEqual({m["id"] for m in json.loads(r.stdout)}, set(helper.MODES))

    def test_apply_refuses_unknown_mode_and_non_root(self):
        exe = str(ROOT / "root" / "netmode-root")
        for argv in (["apply", "turbo"], ["apply", "../etc"], ["apply"], ["apply", "video", "x"]):
            r = subprocess.run([sys.executable, "-I", exe, *argv], capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0, argv)
        if os.geteuid() != 0:
            r = subprocess.run([sys.executable, "-I", exe, "apply", "video"], capture_output=True, text=True)
            self.assertEqual(r.returncode, 77)


class RangeHandler(http.server.BaseHTTPRequestHandler):
    payload = bytes(range(256)) * 20000          # 5.1 MB, position-dependent
    ranges = True

    def log_message(self, *a):
        pass

    def do_GET(self):
        data, rng = self.payload, self.headers.get("Range")
        if rng and self.ranges:
            a, b = rng.split("=")[1].split("-")
            a, b = int(a), min(int(b), len(data) - 1)
            self.send_response(206)
            self.send_header("Content-Range", "bytes %d-%d/%d" % (a, b, len(data)))
            self.send_header("Content-Length", str(b - a + 1))
            self.end_headers()
            self.wfile.write(data[a:b + 1])
        else:
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)


class Downloader(unittest.TestCase):
    def serve(self, ranges):
        handler = type("H", (RangeHandler,), {"ranges": ranges})
        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        self.addCleanup(srv.shutdown)
        return "http://127.0.0.1:%d/file.bin" % srv.server_address[1]

    def fetch(self, ranges, n):
        url = self.serve(ranges)
        cwd = os.getcwd()
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            os.chdir(d)
            try:
                args = cli.argparse.Namespace(url=url, output="out.bin", connections=n)
                with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(cli.cmd_get(args), 0)
                return Path("out.bin").read_bytes(), os.path.exists("out.bin.part")
            finally:
                os.chdir(cwd)

    def test_segmented_download_is_byte_exact(self):
        data, leftover = self.fetch(True, 8)
        self.assertEqual(data, RangeHandler.payload)
        self.assertFalse(leftover)

    def test_falls_back_to_one_stream_without_ranges(self):
        data, _ = self.fetch(False, 8)
        self.assertEqual(data, RangeHandler.payload)


class Helpers(unittest.TestCase):
    def test_ping_parse(self):
        text = ("5 packets transmitted, 5 received, 0% packet loss, time 802ms\n"
                "rtt min/avg/max/mdev = 0.998/2.655/4.298/1.446 ms\n")
        orig = cli.out
        cli.out = lambda *a, **k: text
        try:
            p = cli.ping("1.1.1.1")
        finally:
            cli.out = orig
        self.assertEqual((p["avg"], p["jitter"], p["loss"]), (2.655, 1.446, 0.0))

    def test_video_window_match(self):
        clients = [
            {"class": "org.omarchy.agent", "title": "AnimeLib notes"},
            {"class": "chromium", "title": "Серия 11 • AnimeLIB – Chromium"},
        ]
        cfg = dict(cli.DEFAULT_CONFIG)
        orig = cli.out
        cli.out = lambda *a, **k: json.dumps(clients)
        try:
            self.assertTrue(cli.video_window_open(cfg))
            clients[1]["title"] = "YouTube – Chromium"
            self.assertFalse(cli.video_window_open(cfg))     # a terminal titled AnimeLib is not video
        finally:
            cli.out = orig


if __name__ == "__main__":
    unittest.main()
