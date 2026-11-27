import sys
try:
    from lupa.luajit21 import LuaRuntime
except ImportError:
    from lupa.luajit20 import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
g = lua.globals()
g.ROOT = "K:/jimmyproject/Tactical Infantry Framework/Tactical Infantry Framework/addon/lua/"
g.CLIPS = "K:/jimmyproject/Tactical Infantry Framework/Tactical Infantry Framework/addon/lua/tif/gta/clips/mw_male.lua"
if "--strict" not in sys.argv:
    lua.execute(open(__file__.replace("run.py", "_ws.lua"), encoding="utf-8").read())
lua.execute(open(sys.argv[1], encoding="utf-8").read())
