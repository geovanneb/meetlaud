#!/usr/bin/env python3
"""Downloads a language model from the app's catalog, at its pinned revision, and checks every file's SHA-256.

Usage: python3 -I fetch-model.py <model id> <folder>      e.g. qwen35-2b ~/models/qwen35-2b
"""
import hashlib
import json
import pathlib
import sys
import urllib.request

catalog = pathlib.Path(__file__).resolve().parents[2] / "Packages/Infrastructure/ModelDelivery/Sources/Resources/models.json"
model_id, folder = sys.argv[1], pathlib.Path(sys.argv[2]).expanduser()
models = json.loads(catalog.read_text())
models = models if isinstance(models, list) else models["models"]
model = next(m for m in models if m["id"] == model_id)
folder.mkdir(parents=True, exist_ok=True)
for file in model["files"]:
    target = folder / file["path"]
    if not (target.exists() and target.stat().st_size == file["size"]):
        print(f"downloading {file['path']}")
        urllib.request.urlretrieve(file["url"], target)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    if digest != file["sha256"]:
        sys.exit(f"{file['path']}: SHA-256 does not match the catalog")
print(f"{model_id} ready in {folder}")
