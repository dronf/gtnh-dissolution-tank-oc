"""Host-side Lua simulator. pip install lupa, or provide its directory on PYTHONPATH."""
from pathlib import Path
import os
import json
from lupa import LuaRuntime
p=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path = ... .. '/?.lua;' .. package.path",p.as_posix())
for f in p.glob('*.lua'):
    lua.execute('assert(load(...))',f.read_text(encoding='utf-8'))
total=0
lua.globals().testRoot=p.as_posix()
lua.globals().installerPayloads=lua.table_from({name:(p/name).read_text(encoding='utf-8') for name in ['dt.lua','dt_core.lua','dt_io.lua','dt_bindings.lua','recipes.lua','config.lua']})
lua.globals().registryFixture=lua.table_from(json.loads((p/'tests/fixtures/gtnh-2.9-identities.json').read_text(encoding='utf-8')),recursive=True)
for name, fixture in [('controller_test.lua','coreFixture'),('io_test.lua','ioFixture'),('external_test.lua','externalFixture'),('bindings_test.lua','bindingsFixture'),('installer_test.lua','installerFixture')]:
    result=lua.execute((p/'tests'/name).read_text(encoding='utf-8'))
    lua.globals()[fixture]=result
    total += result['checks']
print(f'TOTAL: {total} simulated assertions passed.',flush=True)
