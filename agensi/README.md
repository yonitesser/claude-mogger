# Agensi edition

`agensi/mogger/` is mogger packed as one skill (SKILL.md + references, hook
scripts, check scripts). It is built from the plugin; do not edit it by hand.

- Rebuild: `bash scripts/build-agensi-skill.sh` (edit `agensi/SKILL.template.md` for the main text).
- Zip for upload: `cd agensi && zip -r mogger-skill.zip mogger`
- Guards live in the SKILL.md frontmatter and run from `.claude/mogger-skill/` in the user's project. `install.sh` puts them there.

UNVERIFIED: that Agensi delivers the extra files (scripts, hooks) to the buyer, and that its 8-point scan accepts the guard scripts (they contain patterns such as `rm -rf` on purpose). Ask Agensi.
