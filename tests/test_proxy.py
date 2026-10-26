import http.client
import http.server
import json
import importlib.machinery
import importlib.util
import os
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("netmode_cli_p", str(ROOT / "bin" / "netmode"))
spec = importlib.util.spec_from_loader("netmode_cli_p", loader)
cli = importlib.util.module_from_spec(spec)
loader.exec_module(cli)

PAYLOAD = os.urandom(5_000_000)
TOKEN = "a1" * 16


class FakeVideo(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    slow_first = set()                                  # span starts served slowly once
    hits = []                                           # (start, end) of every range asked
    referers = []

    def log_message(self, *a):
        pass

    def do_GET(self):
        FakeVideo.referers.append(self.headers.get("Referer"))
        if self.path.startswith("//noranges") or self.path.startswith("/noranges"):
            self.send_response(200)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Content-Length", str(len(PAYLOAD)))
            self.end_headers()
            self.wfile.write(PAYLOAD)
            return
        if "missing" in self.path:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if "moved" in self.path:
            self.send_response(302)
            self.send_header("Location", "https://example.org/real.mp4")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        rng = self.headers.get("Range")
        a, b = rng.split("=")[1].split("-")
        a, b = int(a), min(int(b), len(PAYLOAD) - 1)
        FakeVideo.hits.append((a, b))
        if a in self.slow_first:
            self.slow_first.discard(a)
            self.send_response(206)
            self.send_header("Content-Range", "bytes %d-%d/%d" % (a, b, len(PAYLOAD)))
            self.send_header("Content-Length", str(b - a + 1))
            self.end_headers()
            try:
                for i in range(a, b + 1, 20000):         # ~100 KB/s
                    self.wfile.write(PAYLOAD[i:min(i + 20000, b + 1)])
                    time.sleep(0.2)
            except OSError:
                pass
            return
        self.send_response(206)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Content-Range", "bytes %d-%d/%d" % (a, b, len(PAYLOAD)))
        self.send_header("Content-Length", str(b - a + 1))
        self.end_headers()
        try:
            self.wfile.write(PAYLOAD[a:b + 1])
        except OSError:
            pass


class LocalOrigin(cli.Origin):
    def __init__(self, port):
        super().__init__("http")
        self.port = port

    def connect(self, host):
        return http.client.HTTPConnection("127.0.0.1", self.port, timeout=15)


class ProxyCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        origin = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeVideo)
        origin.daemon_threads = True
        threading.Thread(target=origin.serve_forever, daemon=True).start()
        cls.origin_srv = origin
        cls.proxy = cli.make_proxy(
            0, TOKEN, origin=LocalOrigin(origin.server_address[1]), exclude=[r"^excluded\.test$"],
            referers=[[r"^ref\.test$", "https://ref.example/"]], check_host=lambda h: h != "private.test")
        threading.Thread(target=cls.proxy.serve_forever, daemon=True).start()
        cls.port = cls.proxy.server_address[1]

    @classmethod
    def tearDownClass(cls):
        cls.proxy.shutdown()
        cls.proxy.server_close()
        cls.origin_srv.shutdown()
        cls.origin_srv.server_close()

    def get(self, path="/video1.test/a/b.mp4", method="GET", **headers):
        if not path.startswith("/ping") and not path.startswith("/bypass") and not path.startswith("/stats"):
            path = "/" + TOKEN + path
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=30)
        c.request(method, path, headers=headers)
        r = c.getresponse()
        body = r.read()
        c.close()
        return r, body


class Proxy(ProxyCase):
    def test_whole_file_without_range(self):
        r, body = self.get()
        self.assertEqual(r.status, 200)
        self.assertEqual(body, PAYLOAD)

    def test_open_ended_range_crosses_span_boundaries(self):
        r, body = self.get(Range="bytes=123456-")
        self.assertEqual(r.status, 206)
        self.assertEqual(body, PAYLOAD[123456:])
        self.assertEqual(r.getheader("Content-Range"), "bytes 123456-4999999/5000000")

    def test_closed_and_suffix_ranges(self):
        r, body = self.get(Range="bytes=1000-2999999")
        self.assertEqual(body, PAYLOAD[1000:3000000])
        r, body = self.get(Range="bytes=-500")
        self.assertEqual(body, PAYLOAD[-500:])

    def test_head_has_length_and_no_body(self):
        r, body = self.get(method="HEAD", Range="bytes=0-99")
        self.assertEqual((r.status, body), (206, b""))
        self.assertEqual(r.getheader("Content-Length"), "100")

    def test_unsatisfiable_range(self):
        r, _ = self.get(Range="bytes=9000000-")
        self.assertEqual(r.status, 416)

    def test_wrong_token_is_refused(self):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        c.request("GET", "/" + "b2" * 16 + "/video1.test/a.mp4", headers={"Range": "bytes=0-"})
        self.assertEqual(c.getresponse().status, 403)
        c.close()
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        c.request("GET", "/video1.test/a.mp4")
        self.assertEqual(c.getresponse().status, 403)
        c.close()

    def test_ping(self):
        r, body = self.get("/ping")
        self.assertEqual(body, b"netmode-proxy")

    def bypassed(self):
        return json.loads(self.get("/bypass")[1])

    def test_private_and_excluded_hosts_are_refused_and_listed(self):
        self.assertEqual(self.get("/private.test/a.mp4", Range="bytes=0-")[0].status, 403)
        self.assertEqual(self.get("/excluded.test/a.mp4", Range="bytes=0-")[0].status, 403)
        self.assertLessEqual({"private.test", "excluded.test"}, set(self.bypassed()))

    def test_a_server_without_ranges_is_relayed_and_bypassed(self):
        r, body = self.get("/norange.test/noranges.mp4", Range="bytes=100-")
        self.assertEqual(r.status, 200)
        self.assertEqual(body, PAYLOAD)
        self.assertIn("norange.test", self.bypassed())

    def test_errors_are_relayed_and_bypassed(self):
        r, _ = self.get("/gone.test/missing.mp4", Range="bytes=0-")
        self.assertEqual(r.status, 404)
        self.assertIn("gone.test", self.bypassed())

    def test_redirects_are_relayed_without_bypass(self):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        c.request("GET", "/" + TOKEN + "/hop.test/moved.mp4", headers={"Range": "bytes=0-"})
        r = c.getresponse()
        r.read()
        self.assertEqual((r.status, r.getheader("Location")), (302, "https://example.org/real.mp4"))
        self.assertNotIn("hop.test", self.bypassed())

    def test_referer_comes_from_the_config_not_the_page(self):
        FakeVideo.referers.clear()
        self.get("/ref.test/r.mp4", Range="bytes=0-99", Referer="https://evil.example/")
        self.get("/video9.test/r.mp4", Range="bytes=0-99")
        self.assertEqual(FakeVideo.referers, ["https://ref.example/", None])

    def test_a_throttled_connection_is_replaced(self):
        FakeVideo.slow_first.add(1 << 20)               # the second span starts slow
        t0 = time.monotonic()
        r, body = self.get("/video2.test/slow.mp4", Range="bytes=0-")
        took = time.monotonic() - t0
        self.assertEqual(body, PAYLOAD)
        self.assertLess(took, 12, "a 1 MB span at 100 KB/s would need ~20 s without the retry")


class Cache(ProxyCase):
    def test_a_second_read_is_served_from_memory(self):
        self.get("/video3.test/c.mp4", Range="bytes=0-")
        FakeVideo.hits.clear()
        r, body = self.get("/video3.test/c.mp4", Range="bytes=0-")
        self.assertEqual(body, PAYLOAD)
        self.assertEqual(FakeVideo.hits, [])

    def test_prefetch_runs_ahead_of_a_slow_reader(self):
        FakeVideo.hits.clear()
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=30)
        c.request("GET", "/" + TOKEN + "/video4.test/d.mp4", headers={"Range": "bytes=0-"})
        r = c.getresponse()
        r.read(1000)                                    # read almost nothing
        time.sleep(1.0)
        fetched = sum(b - a + 1 for a, b in FakeVideo.hits)
        c.close()
        self.assertGreater(fetched, 1_000_000)          # the proxy kept fetching on its own


class SpanCacheTests(unittest.TestCase):
    def test_read_returns_the_tail_of_the_segment(self):
        c = cli.SpanCache(1000)
        c.add("k", 100, b"abcdefghij")
        self.assertEqual(bytes(c.read("k", 103)), b"defghij")
        self.assertIsNone(c.read("k", 110))
        self.assertIsNone(c.read("other", 100))

    def test_least_recently_used_goes_first(self):
        c = cli.SpanCache(25)
        c.add("k", 0, b"a" * 10)
        c.add("k", 10, b"b" * 10)
        c.read("k", 0)                                  # touch the first one
        c.add("k", 20, b"c" * 10)                       # over the limit: evicts the second
        self.assertIsNotNone(c.read("k", 0))
        self.assertIsNone(c.read("k", 10))
        self.assertLessEqual(c.size, 25)


class RangeParsing(unittest.TestCase):
    def test_parse_range(self):
        self.assertEqual(cli.parse_range(None, 100), (0, 99))
        self.assertEqual(cli.parse_range("bytes=10-", 100), (10, 99))
        self.assertEqual(cli.parse_range("bytes=10-20", 100), (10, 20))
        self.assertEqual(cli.parse_range("bytes=10-500", 100), (10, 99))
        self.assertEqual(cli.parse_range("bytes=-30", 100), (70, 99))
        self.assertIsNone(cli.parse_range("bytes=100-", 100))

    def test_spans_cover_the_range_exactly(self):
        got = list(cli.spans(5, 30_000_000))
        self.assertEqual(got[0][0], 5)
        self.assertEqual(got[-1][1], 30_000_000)
        for (a, b), (c, d) in zip(got, got[1:]):
            self.assertEqual(c, b + 1)
        self.assertLessEqual(max(b - a + 1 for a, b in got), cli.SPAN_MAX)


if __name__ == "__main__":
    unittest.main()
