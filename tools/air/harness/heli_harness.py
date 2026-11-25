import sys
from lupa.luajit21 import LuaRuntime
root = sys.argv[1].replace("\\", "/").rstrip("/") + "/"
L = LuaRuntime()
src = open(sys.argv[2], encoding="utf-8").read()
f = L.execute("return function(s, root) local f, e = loadstring(s, 'harness') if not f then error(e) end return f(root) end")
f(src, root)
