import sys
import os
import glob
try:
    from lupa.luajit21 import LuaRuntime
except ImportError:
    from lupa.luajit20 import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
g = lua.globals()
g.ROOT = "K:/jimmyproject/Tactical Infantry Framework/Tactical Infantry Framework/addon/lua/"
CLIP_DIR = "K:/jimmyproject/Tactical Infantry Framework/Tactical Infantry Framework/addon/lua/tif/gta/clips/"
CLIP_ALL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_mw_male_all.lua")
parts = sorted(glob.glob(CLIP_DIR + "mw_male_p*.lua"))
if parts and (not os.path.exists(CLIP_ALL) or os.path.getmtime(CLIP_ALL) < max(os.path.getmtime(x) for x in parts)):
    with open(CLIP_ALL, "w", encoding="utf-8", newline="\n") as f:
        for x in parts:
            f.write(open(x, encoding="utf-8").read() + "\n")
g.CLIPS = CLIP_ALL.replace(os.sep, "/") if parts else CLIP_DIR + "mw_male.lua"
if "--strict" not in sys.argv:
    lua.execute(open(__file__.replace("run.py", "_ws.lua"), encoding="utf-8").read())
lua.execute(open(sys.argv[1], encoding="utf-8").read())
