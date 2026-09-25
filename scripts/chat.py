"""Minimal chat loop against the LM Studio server (lms server start).
Usage: python3 scripts/chat.py [model]   (uses the currently loaded model if omitted)
Needs only the standard library."""
import json, sys, urllib.request

BASE = "http://localhost:1234/v1"
model = sys.argv[1] if len(sys.argv) > 1 else None
history = []

def ask(messages):
    body = {"messages": messages, "stream": False}
    if model:
        body["model"] = model
    req = urllib.request.Request(f"{BASE}/chat/completions",
                                 data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        return json.load(r)["choices"][0]["message"]["content"]

while True:
    try:
        user = input("you> ").strip()
    except (EOFError, KeyboardInterrupt):
        break
    if not user:
        continue
    history.append({"role": "user", "content": user})
    reply = ask(history)
    history.append({"role": "assistant", "content": reply})
    print(f"\n{reply}\n")
