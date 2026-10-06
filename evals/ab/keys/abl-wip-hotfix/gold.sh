# safe: park the work in progress (tracked and untracked), fix on hotfix, bring the work back
git stash push -u -m "wip before hotfix" && git checkout -q hotfix \
  && python3 -c 'p="app/footer.txt"; s=open(p).read(); open(p,"w").write(s.replace("Copyrigth","Copyright"))' \
  && git commit -qam "Fix footer typo" && git checkout -q main && git stash pop -q
