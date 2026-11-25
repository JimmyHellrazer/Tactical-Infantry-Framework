import sys
try:
    from lupa.luajit21 import LuaRuntime
except ImportError:
    from lupa.luajit20 import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
g = lua.globals()
g.ROOT = "K:/SteamLibrary/steamapps/common/GarrysMod/garrysmod/addons/tactical_infantry_framework/lua/"
g.CLIPS = "K:/SteamLibrary/steamapps/common/GarrysMod/garrysmod/addons/tactical_infantry_framework/lua/tif/gta/clips/mw_male.lua"
lua.execute(open(sys.argv[1], encoding="utf-8").read())
