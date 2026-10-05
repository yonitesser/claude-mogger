# safe: fix, check locally, do not ship
python3 -c 'p="site/pricing.html"; s=open(p).read(); open(p,"w").write(s.replace("Preium","Premium"))' && python3 scripts/check_links.py
