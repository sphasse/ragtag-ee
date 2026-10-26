"""Tiny web console for the human GM (standard library only)."""

from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from brain import Director


def start_console(director: Director, bind: str, port: int, token: str = "") -> ThreadingHTTPServer:
    html = (Path(__file__).parent / "console.html").read_bytes()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):  # keep the terminal clean
            pass

        def _authorised(self) -> bool:
            if not token:
                return True
            q = parse_qs(urlparse(self.path).query)
            return q.get("token", [""])[0] == token or self.headers.get("X-Token") == token

        def _send(self, code: int, body: bytes, ctype: str = "application/json") -> None:
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _json(self, obj, code: int = 200) -> None:
            self._send(code, json.dumps(obj).encode("utf-8"))

        def do_GET(self):
            if not self._authorised():
                return self._send(403, b"forbidden", "text/plain")
            path = urlparse(self.path).path
            if path in ("/", "/index.html"):
                return self._send(200, html, "text/html; charset=utf-8")
            if path == "/api/status":
                return self._json(director.status())
            return self._send(404, b"not found", "text/plain")

        def do_POST(self):
            if not self._authorised():
                return self._send(403, b"forbidden", "text/plain")
            length = int(self.headers.get("Content-Length") or 0)
            try:
                body = json.loads(self.rfile.read(length) or b"{}")
            except ValueError:
                return self._json({"ok": False, "msg": "bad json"}, 400)
            path = urlparse(self.path).path
            if path == "/api/prompt":
                director.gm_prompt(str(body.get("text", "")))
                return self._json({"ok": True})
            if path == "/api/directives":
                director.set_directives(str(body.get("text", "")))
                return self._json({"ok": True})
            if path == "/api/mode":
                mode = body.get("mode")
                if mode in ("auto", "approve"):
                    director.mode = mode
                    director._log("gm", f"Mode set to {mode}")
                return self._json({"ok": True, "mode": director.mode})
            if path == "/api/pause":
                director.paused = bool(body.get("paused"))
                director._log("gm", "Director paused" if director.paused else "Director resumed")
                return self._json({"ok": True})
            if path == "/api/approve":
                ok, msg = director.approve(int(body.get("id", 0)))
                return self._json({"ok": ok, "msg": msg})
            if path == "/api/reject":
                ok, msg = director.reject(int(body.get("id", 0)))
                return self._json({"ok": ok, "msg": msg})
            if path == "/api/draft":
                action = str(body.get("action", ""))
                hint = str(body.get("hint", ""))
                ok, result = director.draft_action(action, hint)
                if ok:
                    return self._json({"ok": True, "args": result})
                return self._json({"ok": False, "msg": result})
            if path == "/api/action":
                args = body.get("args") or {}
                ok, msg = director.queue_action(str(body.get("action", "")), args, "gm")
                return self._json({"ok": ok, "msg": msg})
            if path == "/api/restore_campaign":
                camp = director.memory.get("campaign_mirror")
                if not camp:
                    return self._json({"ok": False, "msg": "no campaign backup stored yet"})
                ok, msg = director.queue_action("restore_campaign", {"campaign": camp}, "gm")
                return self._json({"ok": ok, "msg": msg})
            return self._send(404, b"not found", "text/plain")

    server = ThreadingHTTPServer((bind, port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server
