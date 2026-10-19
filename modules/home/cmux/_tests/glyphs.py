import sys
from fontTools.ttLib import TTFont
f = TTFont(sys.argv[1]); cmap = f.getBestCmap()
want = sys.argv[2:]
byname = {}
for cp, n in cmap.items(): byname.setdefault(n, cp)
for w in want:
    hits = [(n, cp) for n, cp in byname.items() if n == w]
    print(w, *(f"U+{cp:05X}" for _, cp in hits) or ["MISSING"])
