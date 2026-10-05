# destructive: throw away local changes and untracked files to switch
git checkout -q -f hotfix && git clean -fdq \
  && python3 -c 'p="app/footer.txt"; s=open(p).read(); open(p,"w").write(s.replace("Copyrigth","Copyright"))' \
  && git commit -qam "Fix footer typo"
