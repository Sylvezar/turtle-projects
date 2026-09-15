"""Run the Lua test suite through lupa, from the project root.

    py -3 test/drive.py
"""

import sys
import pathlib
from lupa import LuaRuntime

root = pathlib.Path(__file__).resolve().parent.parent

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(f'_G.PROJECT_ROOT = [[{root.as_posix()}]]')
lua.execute(f'package.path = [[{root.as_posix()}]] .. "/?.lua;" .. package.path')

source = (root / "test" / "run.lua").read_text(encoding="utf-8")

try:
    # load() returns (nil, message) on a syntax error, which lupa hands back as
    # a tuple -- report it rather than trying to call it.
    loaded = lua.eval("function(src) return load(src, '@test/run.lua') end")(source)
    if isinstance(loaded, tuple):
        sys.exit(f"test/run.lua failed to compile: {loaded[1]}")
    if loaded is None:
        sys.exit("test/run.lua failed to compile")
    loaded()
except Exception as exc:  # noqa: BLE001 - surface whatever Lua raised
    print(f"\nLua error: {exc}")
    sys.exit(1)
