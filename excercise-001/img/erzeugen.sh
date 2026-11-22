#!/bin/bash
# Erzeugt die SVG-Grafiken aus den Graphviz-Quellen (*.dot).
# Aufruf: bash excercise-001/img/erzeugen.sh
set -e
cd "$(dirname "$0")"
for f in *.dot; do
    if [ "$f" = "automat.dot" ]; then
        dot -Kneato -n -Tsvg "$f" -o "${f%.dot}.svg"   # feste Positionen
    else
        dot -Tsvg "$f" -o "${f%.dot}.svg"
    fi
    echo "${f%.dot}.svg"
done
