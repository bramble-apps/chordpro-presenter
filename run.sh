#!/bin/sh
# Start Bilingual Projector: http://localhost:8080
# (also lets TVs, phones and Chromecasts on your Wi-Fi show the projector)
cd "$(dirname "$0")"
[ -d tools/.venv ] || { python3 -m venv tools/.venv && tools/.venv/bin/pip install -q pychromecast; }
[ -f build/web/index.html ] || flutter build web
exec tools/.venv/bin/python tools/serve.py --port "${1:-8080}"
