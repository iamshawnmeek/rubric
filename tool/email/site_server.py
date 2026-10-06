#!/usr/bin/env python3
"""Serves website/ the way production's Caddy does, for the page test.

    tool/email/site_server.py <port> <api port>

- extensionless paths find their .html page (Caddy's try_files);
- every response carries the production Content-Security-Policy, read from
  tool/deploy/host/website.caddy.template so the two cannot drift, which
  makes the browser enforce exactly what yourrubric.com enforces;
- POST /api/auth/confirm, and nothing else under /api, is forwarded to the
  API's /auth/confirm (Caddy's `handle /api/auth/confirm`).
"""
import http.server
import os
import re
import sys
import urllib.error
import urllib.request

port, api_port = int(sys.argv[1]), int(sys.argv[2])
root = os.path.join(os.path.dirname(__file__), "..", "..")
site = os.path.join(root, "website")
template = open(os.path.join(root, "tool", "deploy", "host", "website.caddy.template")).read()
csp = re.search(r'Content-Security-Policy "([^"]+)"', template).group(1)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=site, **kwargs)

    def end_headers(self):
        self.send_header("Content-Security-Policy", csp)
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def translate_path(self, path):
        local = super().translate_path(path)
        if not os.path.exists(local) and os.path.exists(local + ".html"):
            return local + ".html"
        return local

    def do_POST(self):
        if self.path.split("?")[0] != "/api/auth/confirm":
            self.send_error(404)
            return
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        request = urllib.request.Request(
            f"http://127.0.0.1:{api_port}/auth/confirm",
            data=body,
            method="POST",
            headers={"Content-Type": self.headers.get("Content-Type", "application/json")},
        )
        try:
            with urllib.request.urlopen(request) as r:
                status, payload = r.status, r.read()
        except urllib.error.HTTPError as e:
            status, payload = e.code, e.read()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
