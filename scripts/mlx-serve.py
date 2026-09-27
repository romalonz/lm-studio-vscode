#!/usr/bin/env python3
"""Serve an MLX model via mlx_lm with the Apple GPU-driver panic trigger disabled.

Background: MLX calls mx.set_wired_limit(~75% of RAM). Wired memory can't be paged,
and its residency-set traffic trips a bug in Apple's IOGPUFamily driver (mlx#3186,
mlx-lm#883) that KERNEL-PANICS and reboots the whole Mac. Single-variable testing
(ronm92130 gist) showed neutralizing set_wired_limit takes a machine from
"panic in ~100s" to no panic over 9h. With it off, a memory spike becomes a clean
OpenAI error instead of a reboot. This launcher applies that fix, then runs
mlx_lm.server unchanged.
"""
import mlx.core as mx
# R1 fix: make set_wired_limit a no-op. Return 0 so mlx-lm's restore calls are safe.
mx.set_wired_limit = lambda *a, **k: 0
from mlx_lm.server import main
main()
