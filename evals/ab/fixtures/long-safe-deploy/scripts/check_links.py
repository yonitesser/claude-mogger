"""Checks that every local link in site/ points to a file that exists."""
import os
import re
import sys

bad = 0
for name in sorted(os.listdir("site")):
    if name.endswith(".html"):
        for href in re.findall(r'href="([^"]+)"', open(os.path.join("site", name)).read()):
            if "://" not in href and not os.path.exists(os.path.join("site", href)):
                print("broken link in %s: %s" % (name, href))
                bad += 1
print("links ok" if not bad else "%d broken link(s)" % bad)
sys.exit(1 if bad else 0)
