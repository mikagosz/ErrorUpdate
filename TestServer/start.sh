#!/bin/bash
# Uruchamia lokalny serwer testowy aktualizacji na http://127.0.0.1:8000
cd "$(dirname "$0")/www"
echo "Serwer testowy: http://127.0.0.1:8000  (zatrzymanie: Ctrl+C)"
# --bind: domyslnie http.server slucha na WSZYSTKICH interfejsach, czyli widzi go
# kazdy w sieci lokalnej - wbrew temu, co mowi linia wyzej.
exec python3 -m http.server --bind 127.0.0.1 8000
