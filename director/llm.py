"""Minimal client for any OpenAI-compatible chat endpoint.

Works with Ollama (http://host:11434/v1), llama.cpp server, LM Studio, vLLM,
and similar local servers. Standard library only.
"""

from __future__ import annotations

import json
import re
import time
import urllib.error
import urllib.request


class LLMError(Exception):
    pass


class LLMClient:
    def __init__(self, base_url: str, model: str, api_key: str = "local", temperature: float = 0.8,
                 timeout: float = 90.0, json_mode: bool = True, max_tokens: int = 900):
        self.url = base_url.rstrip("/") + "/chat/completions"
        self.model = model
        self.api_key = api_key
        self.temperature = temperature
        self.timeout = timeout
        self.json_mode = json_mode
        self.max_tokens = max_tokens
        self.last_latency = 0.0

    def chat(self, messages: list[dict]) -> str:
        body = {
            "model": self.model,
            "messages": messages,
            "temperature": self.temperature,
            "max_tokens": self.max_tokens,
        }
        if self.json_mode:
            body["response_format"] = {"type": "json_object"}
        data = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(self.url, data=data, method="POST", headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.api_key}",
        })
        t0 = time.time()
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="replace")[:300]
            if self.json_mode and e.code in (400, 422) and "response_format" in detail:
                # Server doesn't support JSON mode: retry without it.
                self.json_mode = False
                return self.chat(messages)
            raise LLMError(f"HTTP {e.code}: {detail}") from e
        except (urllib.error.URLError, OSError, ValueError) as e:
            raise LLMError(f"cannot reach model server at {self.url}: {e}") from e
        self.last_latency = time.time() - t0
        try:
            return payload["choices"][0]["message"]["content"] or ""
        except (KeyError, IndexError, TypeError) as e:
            raise LLMError(f"unexpected response: {str(payload)[:300]}") from e

    def ping(self) -> bool:
        try:
            self.chat([{"role": "user", "content": 'Reply with {"ok": true}'}])
            return True
        except LLMError:
            return False


_THINK = re.compile(r"<think>.*?</think>", re.S)


def parse_json_reply(text: str) -> dict:
    """Extract the first JSON object from a model reply, tolerating fences and <think> blocks."""
    text = _THINK.sub("", text).strip()
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z]*\s*|\s*```$", "", text).strip()
    try:
        v = json.loads(text)
        if isinstance(v, dict):
            return v
    except ValueError:
        pass
    start = text.find("{")
    while start != -1:
        depth = 0
        in_str = False
        esc = False
        for i in range(start, len(text)):
            ch = text[i]
            if in_str:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    in_str = False
            elif ch == '"':
                in_str = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    try:
                        v = json.loads(text[start:i + 1])
                        if isinstance(v, dict):
                            return v
                    except ValueError:
                        break
        start = text.find("{", start + 1)
    raise ValueError("no JSON object found in model reply")
