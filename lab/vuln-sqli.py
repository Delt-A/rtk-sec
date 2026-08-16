#!/usr/bin/env python3
"""Deliberately SQL-injectable lab target, loopback only.

Exists solely so sqlmap produces a real result block (Parameter/Type/Title/
Payload) to write the rtk-sec sqlmap filter against. Binds to 127.0.0.1 and
refuses anything else.

    ./lab/vuln-sqli.py 8081      then     sqlmap -u 'http://127.0.0.1:8081/?id=1' --batch
"""
import sqlite3
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

db = sqlite3.connect(":memory:", check_same_thread=False)
db.execute("CREATE TABLE users (id INTEGER, name TEXT, pw TEXT)")
db.executemany("INSERT INTO users VALUES (?,?,?)",
               [(1, "alice", "s3cret"), (2, "bob", "hunter2")])
db.commit()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        qs = parse_qs(urlparse(self.path).query)
        ident = qs.get("id", ["1"])[0]
        try:
            # Intentional string interpolation — this is the whole point.
            rows = db.execute(f"SELECT name FROM users WHERE id = {ident}").fetchall()
            body = "".join(f"<p>user: {r[0]}</p>" for r in rows) or "<p>no rows</p>"
            code = 200
        except Exception as exc:
            body = f"<p>SQL error: {exc}</p>"
            code = 200
        payload = f"<html><body><h1>lab</h1>{body}</body></html>".encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8081
    print(f"vulnerable lab on http://127.0.0.1:{port}/?id=1 (loopback only)")
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
