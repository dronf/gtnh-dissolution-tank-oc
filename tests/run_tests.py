"""Host-side Lua simulator. pip install lupa, or provide its directory on PYTHONPATH."""
from pathlib import Path
import os
import json
import re
from lupa.lua52 import LuaRuntime
p=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path = ... .. '/?.lua;' .. package.path",p.as_posix())
for f in p.glob('*.lua'):
    lua.execute('assert(load(...))',f.read_text(encoding='utf-8'))
total=0
lua.globals().testRoot=p.as_posix()
lua.globals().cliSource=(p/'dt.lua').read_text(encoding='utf-8')
revision=re.search(r"local revision='([0-9a-f]{40})'",(p/'install.lua').read_text(encoding='utf-8'))
assert revision,'Installer must pin an immutable commit'
lua.globals().installerRevision=revision[1]
lua.globals().installerPayloads=lua.table_from({name:(p/name).read_text(encoding='utf-8') for name in ['dt.lua','dt_core.lua','dt_io.lua','dt_bindings.lua','recipes.lua','config.lua']})
lua.globals().registryFixture=lua.table_from(json.loads((p/'tests/fixtures/gtnh-2.9-identities.json').read_text(encoding='utf-8')),recursive=True)
for name, fixture in [('controller_test.lua','coreFixture'),('io_test.lua','ioFixture'),('external_test.lua','externalFixture'),('bindings_test.lua','bindingsFixture'),('installer_test.lua','installerFixture'),('journal_test.lua','journalFixture'),('cli_test.lua','cliFixture')]:
    result=lua.execute((p/'tests'/name).read_text(encoding='utf-8'))
    lua.globals()[fixture]=result
    total += result['checks']
print(f'TOTAL: {total} simulated assertions passed.',flush=True)
