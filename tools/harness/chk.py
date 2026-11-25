import sys
from lupa.luajit21 import LuaRuntime
lua = LuaRuntime()
for f in sys.argv[1:]:
    src = open(f, encoding="utf-8").read()
    # GMod Lua extras: != and // comments and continue are not used here; check plain syntax
    r = lua.eval("function(s, n) local f, e = loadstring(s, n) return e end")(src, f)
    print("OK " if r is None else "ERR", f if r is None else r)
