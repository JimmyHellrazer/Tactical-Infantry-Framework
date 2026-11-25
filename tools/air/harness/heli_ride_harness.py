"""Runs heli_ride_harness.lua: a full drop (heli + passengers) on a stub GMod, with TIF's real sv_action.lua, the real
built clip data (tif_mw_anims mw_male.lua) and the Black Hawk's real tags (from the build's skeleton).
usage: python heli_ride_harness.py <TIF addon folder>   (needs lupa; numpy for the tags)"""
import math
import os
import sys

from lupa.luajit21 import LuaRuntime

import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
for _m in ("meshoptimizer", "PIL"):  # heli_build only needs them for building; the skeleton reader doesn't
    if _m not in sys.modules:
        try:
            __import__(_m)
        except ImportError:
            mod = types.ModuleType(_m)
            mod.Image = None
            sys.modules[_m] = mod
import heli_build as hb  # noqa: E402

tif = sys.argv[1].replace("\\", "/").rstrip("/") + "/"
addons = os.path.dirname(tif.rstrip("/")).replace("\\", "/") + "/"
tags = []
for vid in ("blackhawk", "littlebird", "mi8", "heavy"):
    nodes, skel, _, _ = hb.read_smd_skeleton(hb.VEHICLES[vid]["smd"])
    W = hb.world_matrices(nodes, skel)
    keep = set(hb.VEHICLES[vid]["tags"])
    rows = []
    for i, (n, _) in nodes.items():
        if n in keep:
            M = W[i]
            rows.append('["%s"] = { %.3f, %.3f, %.3f, %.3f }' % (n, M[0, 3], M[1, 3], M[2, 3], math.degrees(math.atan2(M[1, 0], M[0, 0]))))
    tags.append("%s = { %s }" % (vid, ", ".join(rows)))
L = LuaRuntime()
src = open(os.path.join(HERE, "heli_ride_harness.lua"), encoding="utf-8").read()
f = L.execute("return function(s, tif, addons, tags) local f, e = loadstring(s, 'ride_harness') if not f then error(e) end "
              "local t = loadstring('return {' .. tags .. '}')() return f(tif, addons, t) end")
f(src, tif, addons, ", ".join(tags))
