"""Runs tests/run.lua with the LuaJIT bundled in the lupa package, for machines without Lua.

    python tests/lupa_run.py [run.lua arguments]

CI runs tests/run.lua with Lua 5.1 directly.
"""
import os
import site
import sys

sys.path.append(site.getusersitepackages())
from lupa import luajit21  # noqa: E402

here = os.path.dirname(os.path.abspath(__file__))
lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
lua.execute("arg = {}")
arg = lua.globals().arg
arg[0] = os.path.join(here, "run.lua").replace("\\", "/")
for i, a in enumerate(sys.argv[1:], start=1):
    arg[i] = a
lua.execute('local f = assert(loadfile(arg[0])) f()')
