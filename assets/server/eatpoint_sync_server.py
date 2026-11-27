#!/usr/bin/env python3
"""EatPoint sync server: tiny blob store over HTTP(S). Python 3 stdlib only."""
import argparse
import hmac
import json
import os
import re
import sqlite3
import ssl
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit

VERSION = "1"
MAX_BODY = 5 * 1024 * 1024
HOUSEHOLD_RE = re.compile(r"^[0-9a-f]{32,64}$")
NAME_RE = re.compile(r"^[A-Za-z0-9._-]{1,120}$")


class Store:
    def __init__(self, path):
        self.path = path
        self.lock = threading.Lock()
        d = os.path.dirname(os.path.abspath(path))
        os.makedirs(d, exist_ok=True)
        with self._conn() as c:
            c.execute(
                "CREATE TABLE IF NOT EXISTS blobs("
                "household TEXT NOT NULL, name TEXT NOT NULL, data BLOB NOT NULL, "
                "updated_at INTEGER NOT NULL, PRIMARY KEY(household, name))"
            )

    def _conn(self):
        return sqlite3.connect(self.path, timeout=30)

    def names(self, household):
        with self.lock:
            c = self._conn()
            try:
                rows = c.execute(
                    "SELECT name FROM blobs WHERE household=? ORDER BY name", (household,)
                ).fetchall()
            finally:
                c.close()
        return [r[0] for r in rows]

    def get(self, household, name):
        with self.lock:
            c = self._conn()
            try:
                row = c.execute(
                    "SELECT data FROM blobs WHERE household=? AND name=?", (household, name)
                ).fetchone()
            finally:
                c.close()
        return None if row is None else bytes(row[0])

    def put(self, household, name, data):
        with self.lock:
            c = self._conn()
            try:
                with c:
                    c.execute(
                        "INSERT OR REPLACE INTO blobs(household,name,data,updated_at) VALUES(?,?,?,?)",
                        (household, name, sqlite3.Binary(data), int(time.time())),
                    )
            finally:
                c.close()


def make_handler(store, token):
    token_b = token.encode()

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        server_version = "EatPointSync/" + VERSION

        def log_message(self, fmt, *args):
            pass

        def _log(self, status):
            path = urlsplit(self.path).path
            sys.stderr.write(
                "%s %s %s -> %s\n" % (self.client_address[0], self.command, path, status)
            )
            sys.stderr.flush()

        def _drain(self):
            if self._drained:
                return
            self._drained = True
            if self.command != "PUT":
                return
            try:
                left = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                return
            if left < 0 or left > 64 * 1024 * 1024:
                return
            while left > 0:
                chunk = self.rfile.read(min(65536, left))
                if not chunk:
                    break
                left -= len(chunk)

        def _send(self, status, body=b"", ctype="application/json", close=False):
            if status != 204 and status != 200:
                self._drain()
            self.send_response(status)
            if status != 204:
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(body)))
            else:
                self.send_header("Content-Length", "0")
            if close:
                self.send_header("Connection", "close")
                self.close_connection = True
            self.end_headers()
            if body and status != 204 and self.command != "HEAD":
                self.wfile.write(body)
            self._log(status)

        def _json(self, status, obj, **kw):
            self._send(status, json.dumps(obj).encode(), **kw)

        def _authorized(self):
            h = self.headers.get("Authorization", "")
            if not h.startswith("Bearer "):
                return False
            return hmac.compare_digest(h[7:].strip().encode(), token_b)

        def _route(self):
            parts = [unquote(p) for p in urlsplit(self.path).path.split("/")]
            # leading "" from the first slash
            if parts and parts[0] == "":
                parts = parts[1:]
            return parts

        def _handle(self):
            parts = self._route()
            m = self.command
            if parts == ["health"] and m == "GET":
                return self._json(200, {"ok": True, "version": VERSION})
            is_h = len(parts) >= 3 and parts[0] == "h" and parts[2] == "blobs" and len(parts) <= 4
            if not is_h or m not in ("GET", "PUT") or (len(parts) == 3 and m == "PUT"):
                return self._json(404, {"error": "not found"}, close=False)
            if not self._authorized():
                return self._json(401, {"error": "unauthorized"}, close=False)
            household = parts[1]
            if not HOUSEHOLD_RE.match(household):
                return self._json(400, {"error": "bad household"}, close=False)
            if len(parts) == 3:
                return self._json(200, {"names": store.names(household)})
            name = parts[3]
            if not NAME_RE.match(name):
                return self._json(400, {"error": "bad name"}, close=False)
            if m == "GET":
                data = store.get(household, name)
                if data is None:
                    return self._json(404, {"error": "not found"})
                return self._send(200, data, "application/octet-stream")
            # PUT
            try:
                length = int(self.headers.get("Content-Length", ""))
            except ValueError:
                return self._json(411, {"error": "length required"}, close=True)
            if length < 0:
                return self._json(400, {"error": "bad length"}, close=True)
            if length > MAX_BODY:
                return self._json(413, {"error": "too large"}, close=True)
            self._drained = True
            data = self.rfile.read(length)
            if len(data) != length:
                return self._json(400, {"error": "short body"}, close=True)
            store.put(household, name, data)
            return self._send(204)

        def do_GET(self):
            self._safe()

        def do_PUT(self):
            self._safe()

        def do_POST(self):
            self._safe()

        def do_DELETE(self):
            self._safe()

        def _safe(self):
            self._drained = False
            try:
                self._handle()
            except (BrokenPipeError, ConnectionResetError):
                pass
            except Exception as e:  # noqa
                sys.stderr.write("error: %r\n" % (e,))
                try:
                    self._json(500, {"error": "internal"}, close=True)
                except Exception:
                    pass

    return Handler


def main(argv=None):
    p = argparse.ArgumentParser(description="EatPoint sync server")
    p.add_argument("--db", default=os.environ.get("EATPOINT_DB", "/var/lib/eatpoint/sync.db"))
    p.add_argument("--port", type=int, default=int(os.environ.get("EATPOINT_PORT", "8787")))
    p.add_argument("--host", default=os.environ.get("EATPOINT_HOST", "0.0.0.0"))
    p.add_argument("--token-file", default=os.environ.get("EATPOINT_TOKEN_FILE", "/etc/eatpoint/token"))
    p.add_argument("--tls-cert", default=os.environ.get("EATPOINT_TLS_CERT"))
    p.add_argument("--tls-key", default=os.environ.get("EATPOINT_TLS_KEY"))
    a = p.parse_args(argv)

    with open(a.token_file, "r") as f:
        token = f.readline().strip()
    if not token:
        sys.stderr.write("token file is empty\n")
        return 2
    store = Store(a.db)
    srv = ThreadingHTTPServer((a.host, a.port), make_handler(store, token))
    srv.daemon_threads = True
    if a.tls_cert:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(a.tls_cert, a.tls_key)
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    sys.stderr.write("listening on %s:%d\n" % (a.host, a.port))
    sys.stderr.flush()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
