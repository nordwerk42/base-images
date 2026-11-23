import sys
import json
import hashlib
import os
import platform

print(f"Python {sys.version}")
print(f"Platform: {platform.machine()}")

# JSON roundtrip
data = {"status": "ok", "values": [1, 2, 3]}
assert json.loads(json.dumps(data)) == data, "json roundtrip failed"

# Basic arithmetic
assert sum(range(1, 101)) == 5050, "arithmetic failed"

# hashlib
digest = hashlib.sha256(b"test").hexdigest()
assert len(digest) == 64, "hashlib failed"

# pdb module is available (key debug tool)
import pdb
assert hasattr(pdb, "set_trace"), "pdb not available"

# faulthandler (used for debugging crashes)
import faulthandler
assert hasattr(faulthandler, "enable"), "faulthandler not available"

print("All tests passed.")
