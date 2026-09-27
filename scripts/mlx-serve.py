#!/usr/bin/env python3
"""One mlx_lm server, models loaded ON DEMAND by name, Apple GPU-driver panic trigger
disabled (mlx#3186). MLX_SERVE_MODELS="name=path;name2=path2": requesting a name loads/
swaps to that model (one resident at a time; the other stays idle/unloaded). Also
advertises the names on /v1/models so OpenAI clients (Cline) show them in the dropdown."""
import os, json as _json, time as _time
import mlx.core as mx
mx.set_wired_limit = lambda *a, **k: 0     # panic fix
from mlx_lm import server as _srv
_models = {}
for pair in os.environ.get("MLX_SERVE_MODELS", "").split(";"):
    if "=" in pair:
        n, p = pair.split("=", 1); _models[n.strip()] = p.strip()
if _models:
    _orig = _srv.ModelProvider.__init__
    def _init(self, cli_args):
        _orig(self, cli_args)
        for n, p in _models.items():
            self.default_model_map[n] = p          # request name -> load that model on demand
    _srv.ModelProvider.__init__ = _init
    def _models_req(self):                          # advertise names on /v1/models
        data = [{"id": n, "object": "model", "created": int(_time.time()), "owned_by": "local"} for n in _models]
        self._set_completion_headers(200); self.end_headers()
        self.wfile.write(_json.dumps({"object": "list", "data": data}).encode())
    _srv.APIHandler.handle_models_request = _models_req
_srv.main()
