#!/bin/bash
# Uruchamia lokalny serwer testowy aktualizacji na http://127.0.0.1:8000
cd "$(dirname "$0")/www"
echo "Serwer testowy: http://127.0.0.1:8000  (zatrzymanie: Ctrl+C)"
exec python3 -m http.server 8000
