#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
# not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Test pages for scripts/perf/xbench.swift, on 127.0.0.1 only.

  python3 -I scripts/perf/bench_server.py <port> <beacon-log>

/page?run=<id>&tab=<n>  a plain page that reports its own first-contentful-paint (Paint Timing API) to /fcp as an
                        absolute time (ms since 1970), so the harness can compare it with the moment it launched the
                        browser. The same page and the same measurement for every browser; no debugging port needed.
/fcp?run=..&tab=..&t=.. appends {"run", "tab", "t"} to the beacon log (one JSON object per line).
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>Bench {tab}</title>
<style>html,body{{margin:0;height:100%;background:#1f6f43;color:#fff;font:28px -apple-system,system-ui,sans-serif}}
main{{padding:48px}}</style></head><body><main><h1>Benchmark page {tab}</h1><p>Run {run}.</p></main>
<script>
new PerformanceObserver(function (list) {{
  for (const e of list.getEntries()) {{
    if (e.name !== 'first-contentful-paint') continue;
    const t = performance.timeOrigin + e.startTime;
    fetch('/fcp?run={run}&tab={tab}&t=' + t.toFixed(1), {{ method: 'POST', keepalive: true }});
  }}
}}).observe({{ type: 'paint', buffered: true }});
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    log_path = ""

    def _query(self):
        url = urlparse(self.path)
        return url.path, {k: v[0] for k, v in parse_qs(url.query).items()}

    def _send(self, code, body=b"", kind="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path, q = self._query()
        if path == "/page":
            run = "".join(c for c in q.get("run", "0") if c.isalnum() or c == "-")[:64]
            tab = "".join(c for c in q.get("tab", "0") if c.isdigit())[:4] or "0"
            self._send(200, PAGE.format(run=run, tab=tab).encode(), "text/html; charset=utf-8")
        elif path == "/fcp":
            self.do_POST()
        else:
            self._send(404)

    def do_POST(self):
        path, q = self._query()
        if path != "/fcp":
            return self._send(404)
        try:
            entry = {"run": q["run"], "tab": int(q["tab"]), "t": float(q["t"])}
        except (KeyError, ValueError):
            return self._send(400)
        with open(Handler.log_path, "a") as f:
            f.write(json.dumps(entry) + "\n")
        self._send(204)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    Handler.log_path = sys.argv[2]
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
