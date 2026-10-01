#!/usr/bin/env bash
# database.sh — database-design report. REPORT-ONLY: never modifies the project.
#
# Usage:  bash scripts/checks/database.sh [project-dir]
# Output: one line per finding:  LEVEL|check-id|message   (PASS WARN FAIL SKIP)
# Always exits 0. Findings cite file:line; name-based rules are "(heuristic)".
#
# Reads: SQL migrations/schemas (*.sql), Prisma (*.prisma), Django and
# SQLAlchemy models (*.py), TypeORM entities and Drizzle tables (*.ts/*.js),
# Supabase migrations (SQL under supabase/).
#
# Check ids: db-primary-key, db-fk-index, db-migrations, db-unique, db-rls,
#            db-backup
# (db-rls is the DB-DESIGN view only; security.sh owns the exposure verdict.)
set -u
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "SKIP|db-primary-key|cannot cd into $ROOT"; exit 0; }
CAP="${MOGGER_CHECK_CAP:-12}"
TMP=$(mktemp -d 2>/dev/null || mktemp -d -t mogger-database) || exit 0
trap 'rm -rf "$TMP"' EXIT
FIND="$TMP/findings"; : > "$FIND"

group() {
  awk -F'|' -v id="$1" -v pm="$2" -v cap="$CAP" '
    $2==id { n++; if (n<=cap) print; else lv=$1 }
    END { if (n==0) print "PASS|" id "|" pm; else if (n>cap) print (lv==""?"WARN":lv) "|" id "|... and " (n-cap) " more finding(s) not shown" }' "$FIND"
}

# ------------------------------------------------------------ discovery
PRUNE_FIND() {
  find . \( -name node_modules -o -name .git -o -name dist -o -name build -o -name venv -o -name .venv \
    -o -name vendor -o -name __pycache__ -o -name .next -o -name .nuxt -o -name target -o -name coverage \
    -o -name .tox -o -name site-packages -o -name .claude -o -name .cache -o -name .turbo \) -prune -o "$@" -print 2>/dev/null | sed 's|^\./||'
}
PRUNE_FIND -type f -name '*.sql' > "$TMP/sql.list"
PRUNE_FIND -type f -name '*.prisma' > "$TMP/prisma.list"
PRUNE_FIND -type f \( -name '*.py' -o -name '*.ts' -o -name '*.js' -o -name '*.mjs' \) > "$TMP/code.list"
tr '\n' '\0' < "$TMP/code.list" > "$TMP/code.z"
if [ -s "$TMP/code.list" ]; then
  xargs -0 grep -l -E 'models[.]Model|__tablename__' < "$TMP/code.z" 2>/dev/null | grep -E '[.]py$' > "$TMP/py.list"
  xargs -0 grep -l -E '@Entity[(]|pgTable[(]|mysqlTable[(]|sqliteTable[(]' < "$TMP/code.z" 2>/dev/null | grep -E '[.](ts|js|mjs)$' > "$TMP/ts.list"
else : > "$TMP/py.list"; : > "$TMP/ts.list"; fi
[ -f "$TMP/py.list" ] || : > "$TMP/py.list"
[ -f "$TMP/ts.list" ] || : > "$TMP/ts.list"

ISSUPA=0
{ [ -d supabase ] || grep -s -q '@supabase' package.json; } && ISSUPA=1

runlist() {  # runlist <list> <awk args...>
  local list="$1"; shift
  [ -s "$list" ] || return 0
  tr '\n' '\0' < "$list" | xargs -0 awk "$@" >> "$FIND" 2>/dev/null
}

# ------------------------------------------------------------ SQL
cat > "$TMP/sql.awk" <<'EOF'
function trim(s) { gsub(/^[[:space:]]+/,"",s); gsub(/[[:space:]]+$/,"",s); return s }
function unq(s) { gsub(/["`]/,"",s); gsub(/[[]/,"",s); gsub(/[]]/,"",s); return s }
function firstid(s,  t) {
  t=s; sub(/^[[:space:]]*[(]?/,"",t)
  while (t ~ /^[[:alnum:]_]+[(]/) sub(/^[[:alnum:]_]+[(]/,"",t)
  t=unq(t)
  if (match(t,/^[[:alnum:]_]+/)) return tolower(substr(t,RSTART,RLENGTH))
  return ""
}
function tname(s) { s=unq(s); sub(/^.*[.]/,"",s); return tolower(s) }
function tschema(s) { s=unq(s); if (index(s,".")==0) return ""; sub(/[.][^.]*$/,"",s); return tolower(s) }
function addtbl(t, sch) { if (!(t in tbl)) { nt++; tl[nt]=t; tbl[t]=sfile ":" sline; tsch[t]=sch; haspk[t]=0 } }
function parens(s,  a, b) { if (match(s,/[(][^)]*[)]/)) return substr(s,RSTART+1,RLENGTH-2); return "" }
function proc(stmt,  u, rest, name, body, i, ch, dep, part, parts, np, up, k, c, nm, after, cb, tn, sc) {
  gsub(/[[:space:]]+/," ",stmt)
  u=toupper(stmt)
  if (u ~ /^ *CREATE( OR REPLACE)?( (GLOBAL|LOCAL))?( (TEMP|TEMPORARY|UNLOGGED))? TABLE /) {
    if (u ~ / PARTITION OF /) return
    if (!match(u,/TABLE( IF NOT EXISTS)? +/)) return
    after=RSTART+RLENGTH
    rest=substr(stmt,after)
    if (!match(rest,/^[^ (]+/)) return
    name=substr(rest,RSTART,RLENGTH)
    tn=tname(name); sc=tschema(name)
    rest=substr(rest,RLENGTH+1)
    if (index(rest,"(")==0) return
    rest=substr(rest,index(rest,"("))
    dep=0; body=""
    for (i=1;i<=length(rest);i++) {
      ch=substr(rest,i,1)
      if (ch=="(") { dep++; if (dep==1) continue }
      if (ch==")") { dep--; if (dep==0) break }
      body=body ch
    }
    if (trim(toupper(body)) ~ /^LIKE /) return
    addtbl(tn, sc)
    # split body on commas at depth 0
    np=0; dep=0; part=""
    for (i=1;i<=length(body);i++) {
      ch=substr(body,i,1)
      if (ch=="(") dep++
      if (ch==")") dep--
      if (ch=="," && dep==0) { parts[++np]=part; part="" } else part=part ch
    }
    parts[++np]=part
    for (k=1;k<=np;k++) {
      part=trim(parts[k]); up=toupper(part)
      if (part=="") continue
      if (up ~ /^(CONSTRAINT [^ ]+ )?PRIMARY KEY/) { haspk[tn]=1; pkc[tn "." firstid(parens(part))]=1 }
      else if (up ~ /^(CONSTRAINT [^ ]+ )?FOREIGN KEY/) { c=firstid(parens(part)); if (c!="") { fk[tn "." c]=1; fkl[tn]=fkl[tn] " " c } }
      else if (up ~ /^(CONSTRAINT [^ ]+ )?UNIQUE/) { cb=parens(part); c=firstid(cb); if (c!="") uq[tn "." c]=1 }
      else if (up ~ /^(INDEX|KEY|FULLTEXT|SPATIAL|UNIQUE INDEX|UNIQUE KEY) /) { c=firstid(parens(part)); if (c!="") { ix[tn "." c]=1; idx[tn "." c]=1; if (up ~ /^UNIQUE/) uq[tn "." c]=1 } }
      else if (up ~ /^(CONSTRAINT|CHECK|EXCLUDE|LIKE|PERIOD) /) { }
      else {
        nm=part; sub(/[[:space:]].*$/,"",nm); nm=tolower(unq(nm))
        if (nm=="") continue
        cols[tn]=cols[tn] " " nm
        if (up ~ / PRIMARY KEY/) { haspk[tn]=1; pkc[tn "." nm]=1 }
        if (up ~ / REFERENCES /) { fk[tn "." nm]=1; fkl[tn]=fkl[tn] " " nm }
        if (up ~ / UNIQUE( |$)/) uq[tn "." nm]=1
        if (up ~ / NOT NULL/ || up ~ / PRIMARY KEY/) nn[tn "." nm]=1
      }
    }
    return
  }
  if (u ~ /^ *ALTER TABLE /) {
    if (!match(u,/ALTER TABLE( ONLY)?( IF EXISTS)? +/)) return
    rest=substr(stmt,RSTART+RLENGTH)
    if (!match(rest,/^[^ ]+/)) return
    tn=tname(substr(rest,RSTART,RLENGTH))
    rest=substr(rest,RLENGTH+1)
    up=toupper(rest)
    if (up ~ /ENABLE ROW LEVEL SECURITY|FORCE ROW LEVEL SECURITY/) rls[tn]=1
    if (up ~ /ADD (CONSTRAINT [^ ]+ )?PRIMARY KEY/) haspk[tn]=1
    if (up ~ /ADD (CONSTRAINT [^ ]+ )?FOREIGN KEY/) { c=firstid(parens(rest)); if (c!="") { fk[tn "." c]=1; fkl[tn]=fkl[tn] " " c; if (!(tn in tbl)) { } } }
    if (up ~ /ADD (CONSTRAINT [^ ]+ )?UNIQUE/) { c=firstid(parens(rest)); if (c!="") uq[tn "." c]=1 }
    if (up ~ /ADD (COLUMN )?(IF NOT EXISTS )?[^ ]+ .* REFERENCES /) { nm=trim(rest); sub(/^[Aa][Dd][Dd] +([Cc][Oo][Ll][Uu][Mm][Nn] +)?([Ii][Ff] +[Nn][Oo][Tt] +[Ee][Xx][Ii][Ss][Tt][Ss] +)?/,"",nm); sub(/[[:space:]].*$/,"",nm); nm=tolower(unq(nm)); fk[tn "." nm]=1; fkl[tn]=fkl[tn] " " nm }
    return
  }
  if (u ~ /^ *CREATE (UNIQUE )?INDEX /) {
    if (!match(u,/ ON (ONLY )?/)) return
    rest=substr(stmt,RSTART+RLENGTH)
    if (!match(rest,/^[^ (]+/)) return
    tn=tname(substr(rest,RSTART,RLENGTH))
    rest=substr(rest,RLENGTH+1)
    if (index(rest,"(")==0) return
    cb=parens(substr(rest,index(rest,"(")))
    c=firstid(cb)
    if (c!="") { idx[tn "." c]=1; if (u ~ /^ *CREATE UNIQUE/ && index(cb,",")==0) uq[tn "." c]=1 }
  }
}
FNR==1 { instmt=0 }
{
  line=$0
  sub(/--.*$/,"",line); gsub(/\/\*[^*]*\*\//,"",line)
  if (line ~ /^[[:space:]]*$/) next
  if (!instmt) {
    if (toupper(line) ~ /^[[:space:]]*(CREATE|ALTER)[[:space:]]/) { instmt=1; stmt=""; sfile=FILENAME; sline=FNR }
    else next
  }
  stmt=stmt " " line
  if (index(line,";")>0) { proc(stmt); instmt=0 }
}
END {
  if (instmt) proc(stmt)
  for (i=1;i<=nt;i++) {
    t=tl[i]; loc=tbl[t]
    if (!haspk[t]) printf "FAIL|db-primary-key|%s: table '%s' has no PRIMARY KEY (rows cannot be uniquely addressed; updates and joins get slow and ambiguous)\n", loc, t
    n=split(fkl[t],a," ")
    for (j=1;j<=n;j++) { c=a[j]; if (seen[t "." c]++) continue
      if (!((t "." c) in idx) && !((t "." c) in pkc) && !((t "." c) in uq)) printf "WARN|db-fk-index|%s: foreign key column '%s.%s' has no index (PostgreSQL does not index FKs automatically: joins and deletes on the parent will scan the table)\n", loc, t, c }
    n=split(cols[t],a," ")
    for (j=1;j<=n;j++) { c=a[j]
      if (c=="email" || c=="username" || c=="user_name" || c=="e_mail") {
        if (!((t "." c) in uq) && !((t "." c) in pkc)) printf "WARN|db-unique|%s: column '%s.%s' has no UNIQUE constraint or unique index (heuristic by column name: duplicates are only prevented in app code)\n", loc, t, c
        else if (!((t "." c) in nn)) printf "WARN|db-unique|%s: column '%s.%s' is unique but nullable (heuristic by column name: add NOT NULL if every row needs one)\n", loc, t, c
      } }
    if (SUPA+0 && (tsch[t]=="" || tsch[t]=="public") && !(t in rls) && index(loc,"supabase")>0) printf "WARN|db-rls|%s: Supabase table '%s' has no ENABLE ROW LEVEL SECURITY in any migration (DB-design view; see security check for exposure)\n", loc, t
  }
  printf "META|sql-tables|%d\n", nt
}
EOF
if [ -s "$TMP/sql.list" ]; then
  tr '\n' '\0' < "$TMP/sql.list" | xargs -0 awk -v SUPA="$ISSUPA" -f "$TMP/sql.awk" > "$TMP/sql.out" 2>/dev/null
  grep -v '^META' "$TMP/sql.out" >> "$FIND"
  NSQL=$(grep '^META|sql-tables|' "$TMP/sql.out" | head -1 | cut -d'|' -f3)
else NSQL=0; fi

# ------------------------------------------------------------ Prisma
cat > "$TMP/prisma.awk" <<'EOF'
function trim(s) { gsub(/^[[:space:]]+/,"",s); gsub(/[[:space:]]+$/,"",s); return s }
function firstlist(s,  t) { if (match(s,/[[][^]]*[]]/)) { t=substr(s,RSTART+1,RLENGTH-2); sub(/,.*$/,"",t); return trim(t) } return "" }
function endmodel(  i, f) {
  if (!haspk) printf "FAIL|db-primary-key|%s:%d: Prisma model '%s' has no @id / @@id (no primary key)\n", mfile, mline, mname
  for (i=1;i<=nfk;i++) { f=fk[i]
    if (!(f in idxf) && provider != "mysql") printf "WARN|db-fk-index|%s:%d: relation field '%s.%s' has no @@index / @unique (Prisma does not index relation fields on PostgreSQL; add @@index([%s]))\n", mfile, fkln[i], mname, f, f }
  for (f in cand) if (!(f in uniq)) printf "WARN|db-unique|%s:%d: field '%s.%s' has no @unique / @@unique (heuristic by field name: duplicates only prevented in app code)\n", mfile, cand[f], mname, f
  inm=0; nfk=0; haspk=0; delete idxf; delete uniq; delete cand
}
/^datasource/ { inds=1 }
inds && /provider[[:space:]]*=/ { p=$0; gsub(/.*=[[:space:]]*"/,"",p); gsub(/".*/,"",p); provider=p }
inds && /^[}]/ { inds=0 }
/^model[[:space:]]+[[:alnum:]_]+[[:space:]]*[{]/ { inm=1; mname=$2; mline=FNR; mfile=FILENAME; haspk=0; nfk=0; next }
inm {
  line=$0
  if (line ~ /^[}]/) { endmodel(); next }
  if (line ~ /^[[:space:]]*\/\//) next
  if (line ~ /@id|@@id/) haspk=1
  if (line ~ /@@id[(]/) { f=firstlist(line); if (f!="") idxf[f]=1 }
  if (line ~ /@relation[(]/ && match(line,/fields:[[:space:]]*[[][^]]*[]]/)) { s=substr(line,RSTART,RLENGTH); nfk++; fk[nfk]=firstlist(s); fkln[nfk]=FNR }
  if (line ~ /@@(index|unique)[(]/) { f=firstlist(line); if (f!="") idxf[f]=1; if (line ~ /@@unique/ && f!="") uniq[f]=1 }
  if (line !~ /^[[:space:]]*@@/ && line ~ /[[:space:]]@(id|unique)/) { f=$1; idxf[f]=1; uniq[f]=1 }
  f=$1
  if (f=="email" || f=="username") cand[f]=FNR
}
EOF
runlist "$TMP/prisma.list" -f "$TMP/prisma.awk"

# ------------------------------------------------------------ Django + SQLAlchemy
cat > "$TMP/py.awk" <<'EOF'
function trim(s) { gsub(/^[[:space:]]+/,"",s); gsub(/[[:space:]]+$/,"",s); return s }
function pcount(s,  o, c) { gsub(/"[^"]*"/,"",s); gsub(/'[^']*'/,"",s); o=gsub(/[(]/,"(",s); c=gsub(/[)]/,")",s); return o-c }
function endclass(  i, f) {
  if (incls && (isdj || issa)) {
    if (issa && !sapk) printf "FAIL|db-primary-key|%s:%d: SQLAlchemy model '%s' has no primary_key=True / PrimaryKeyConstraint\n", cfile, cln, cname
    for (i=1;i<=nc;i++) {
      f=cf[i]
      if (ck[i]=="fk_noindex") { if (issa && !(uctext ~ f)) printf "WARN|db-fk-index|%s:%d: foreign key column '%s.%s' has no index=True / Index() (SQLAlchemy does not index FKs automatically)\n", cfile, cl[i], cname, f }
      else if (ck[i]=="fk_off") printf "WARN|db-fk-index|%s:%d: foreign key '%s.%s' sets db_index=False\n", cfile, cl[i], cname, f
      else if (ck[i]=="nouniq") { if (!(uctext ~ f)) printf "WARN|db-unique|%s:%d: field '%s.%s' has no unique=True / UniqueConstraint (heuristic by field name: duplicates only prevented in app code)\n", cfile, cl[i], cname, f }
    }
  }
  incls=0; nc=0; issa=0; sapk=0; isdj=0; uctext=""
}
function field(stmt, startln,  nm, isfk) {
  nm=stmt; sub(/^[[:space:]]+/,"",nm); sub(/[[:space:]]*[:=].*$/,"",nm)
  if (stmt ~ /primary_key[[:space:]]*=[[:space:]]*True/) sapk=1
  isfk = (stmt ~ /models[.](ForeignKey|OneToOneField)[(]/ || stmt ~ /ForeignKey[(]/)
  if (isfk) {
    if (stmt ~ /db_index[[:space:]]*=[[:space:]]*False/) { nc++; cf[nc]=nm; ck[nc]="fk_off"; cl[nc]=startln }
    else if (issa && stmt !~ /index[[:space:]]*=[[:space:]]*True/ && stmt !~ /primary_key[[:space:]]*=[[:space:]]*True/ && stmt !~ /unique[[:space:]]*=[[:space:]]*True/) { nc++; cf[nc]=nm; ck[nc]="fk_noindex"; cl[nc]=startln }
  }
  if ((nm=="email" || nm=="username") && stmt !~ /unique[[:space:]]*=[[:space:]]*True/ && stmt !~ /primary_key[[:space:]]*=[[:space:]]*True/) { nc++; cf[nc]=nm; ck[nc]="nouniq"; cl[nc]=startln }
}
FNR==1 { endclass(); joining=0 }
/^class[[:space:]]+[[:alnum:]_]+[(]/ {
  endclass()
  if ($0 ~ /Model|Base|DeclarativeBase/) { incls=1; cname=$2; sub(/[(].*/,"",cname); cfile=FILENAME; cln=FNR; nc=0; issa=0; sapk=0; uctext=""; isdj=($0 ~ /models[.]Model/) }
  next
}
incls {
  line=$0
  if (line ~ /^[[:space:]]*#/) next
  if (line ~ /unique_together|UniqueConstraint|Index[(]/) uctext=uctext " " line
  if (line ~ /__tablename__[[:space:]]*=/) issa=1
  if (line ~ /PrimaryKeyConstraint|__mapper_args__/) sapk=1
  if (joining) { stmt=stmt " " trim(line); dep+=pcount(line); if (dep<=0) { joining=0; field(stmt, sln) } next }
  if (line ~ /^[[:space:]]+[[:alnum:]_]+[[:space:]]*(:[^=]*)?=[[:space:]]*(models[.][[:alnum:]]+|(db[.])?(Column|mapped_column)|ForeignKey)[(]/) {
    stmt=line; sln=FNR; dep=pcount(line)
    if (dep<=0) field(stmt, sln); else joining=1
  }
}
END { endclass() }
EOF
runlist "$TMP/py.list" -f "$TMP/py.awk"

# ------------------------------------------------------------ TypeORM + Drizzle
cat > "$TMP/ts.awk" <<'EOF'
function trim(s) { gsub(/^[[:space:]]+/,"",s); gsub(/[[:space:]]+$/,"",s); return s }
function endreg(  i) {
  if (inr) {
    if (!haspk) printf "FAIL|db-primary-key|%s:%d: %s '%s' has no primary key (%s)\n", rfile, rln, kind, rname, (kind=="TypeORM entity" ? "@PrimaryGeneratedColumn/@PrimaryColumn" : "primaryKey()")
    if (nfk>0 && !hasidx) printf "WARN|db-fk-index|%s:%d: %s '%s' has %d relation/foreign key column(s) (first at line %d) but no index (%s)\n", rfile, fkl1, kind, rname, nfk, fkl1, (kind=="TypeORM entity" ? "add @Index" : "add index()")
    for (i=1;i<=nc;i++) if (!cu[i] && !hasuniq) printf "WARN|db-unique|%s:%d: field '%s.%s' has no unique constraint (heuristic by field name: duplicates only prevented in app code)\n", rfile, cln[i], rname, cf[i]
  }
  inr=0; haspk=0; nfk=0; hasidx=0; hasuniq=0; nc=0
}
FNR==1 { endreg(); p1=""; p2=""; p3="" }
/@Entity[(]/ { endreg(); inr=1; kind="TypeORM entity"; rfile=FILENAME; rln=FNR; rname="(entity)"; haspk=0; nfk=0; hasidx=0; hasuniq=0; nc=0 }
/(pgTable|mysqlTable|sqliteTable)[(]/ && !/^[[:space:]]*(\/\/|import)/ {
  endreg(); inr=1; kind="Drizzle table"; rfile=FILENAME; rln=FNR; haspk=0; nfk=0; hasidx=0; hasuniq=0; nc=0
  s=$0; if (match(s,/Table[(]['"][^'"]*['"]/)) { rname=substr(s,RSTART+7,RLENGTH-8) } else rname="(table)"
}
inr {
  line=$0
  if (line ~ /^[[:space:]]*(\/\/|\*)/) { p3=p2; p2=p1; p1=line; next }
  if (line ~ /^[[:space:]]*export[[:space:]]+class[[:space:]]+[[:alnum:]_]+/ && kind=="TypeORM entity" && rname=="(entity)") { s=line; sub(/^.*class[[:space:]]+/,"",s); sub(/[^[:alnum:]_].*$/,"",s); rname=s }
  if (line ~ /@PrimaryGeneratedColumn|@PrimaryColumn|@ObjectIdColumn|primaryKey[(]|[.]primaryKey[(]/) haspk=1
  if (line ~ /@ManyToOne[(]|@OneToOne[(]|[.]references[(]/) { nfk++; if (nfk==1) fkl1=FNR }
  if (line ~ /@Index[(]|[^[:alnum:]]index[(]|uniqueIndex[(]/) hasidx=1
  if (line ~ /@Unique[(]|uniqueIndex[(]|unique[(][)]|unique[(]['"]/) hasuniq=1
  if (line ~ /^[[:space:]]*(email|username)[?!]?[[:space:]]*:/ || line ~ /^[[:space:]]*(email|username)[[:space:]]*:[[:space:]]*(text|varchar|char)[(]/) {
    f=line; sub(/^[[:space:]]+/,"",f); sub(/[^[:alnum:]_].*$/,"",f)
    nc++; cf[nc]=f; cln[nc]=FNR
    cu[nc]=((p1 p2 p3 line) ~ /unique/)
  }
  p3=p2; p2=p1; p1=line
}
END { endreg() }
EOF
runlist "$TMP/ts.list" -f "$TMP/ts.awk"

# ------------------------------------------------------------ has any schema?
NSCHEMA=0
[ "${NSQL:-0}" -gt 0 ] && NSCHEMA=1
[ -s "$TMP/prisma.list" ] && NSCHEMA=1
[ -s "$TMP/py.list" ] && NSCHEMA=1
[ -s "$TMP/ts.list" ] && NSCHEMA=1

# ------------------------------------------------------------ DB used? migrations dir?
DBUSED=$(grep -s -l -i -E 'prisma|sqlalchemy|psycopg|pymysql|mysqlclient|"pg"|"mysql2?"|sequelize|typeorm|drizzle|knex|django|sqlite|supabase|gorm|asyncpg|peewee|alembic' package.json requirements.txt requirements-dev.txt pyproject.toml Pipfile go.mod Gemfile setup.py 2>/dev/null | head -1)
[ "$NSCHEMA" -eq 1 ] && [ -z "$DBUSED" ] && DBUSED="schema files"
MIGDIR=$(PRUNE_FIND -type d \( -name migrations -o -name migrate -o -name alembic -o -name drizzle \) | head -1)
[ -z "$MIGDIR" ] && [ -s "$TMP/sql.list" ] && MIGDIR=$(head -1 "$TMP/sql.list")
if [ -z "$DBUSED" ] && [ "$NSCHEMA" -eq 0 ]; then
  echo "SKIP|db-migrations|no database usage detected (no ORM/driver in manifests, no schema files)" >> "$FIND"
elif [ -n "$MIGDIR" ]; then
  echo "PASS|db-migrations|migrations/schema files present ($MIGDIR)" >> "$FIND"
else
  echo "WARN|db-migrations|database in use ($DBUSED) but no migrations directory or .sql schema files: the schema lives only in app code (heuristic), so it cannot be reviewed, reproduced or rolled back" >> "$FIND"
fi

# ------------------------------------------------------------ backups
if [ -z "$DBUSED" ] && [ "$NSCHEMA" -eq 0 ]; then
  echo "SKIP|db-backup|no database usage detected" >> "$FIND"
else
  BK=$(find . \( -name node_modules -o -name .git -o -name dist -o -name build -o -name venv -o -name .venv -o -name vendor -o -name .next -o -name target \) -prune -o -type f \
        \( -name '*.md' -o -name '*.txt' -o -name '*.yml' -o -name '*.yaml' -o -name '*.sh' -o -name 'Makefile' -o -name 'Dockerfile' -o -name '*.toml' -o -name '*.mdx' \) -print 2>/dev/null \
        | tr '\n' '\0' | xargs -0 grep -H -n -i -E 'backup|pg_dump|mysqldump|snapshot|point-in-time|pitr' 2>/dev/null | head -1 | cut -d: -f1,2)
  if [ -n "$BK" ]; then echo "PASS|db-backup|backup/restore mentioned at ${BK#./} (verify it was actually tested by restoring)" >> "$FIND"
  else echo "WARN|db-backup|no backup plan documented: no backup/pg_dump/snapshot/point-in-time mention in docs, scripts or CI. Hosted databases may back up automatically; confirm and write it down (and test a restore)" >> "$FIND"; fi
fi

# ------------------------------------------------------------ report
if [ "$NSCHEMA" -eq 0 ]; then
  echo "SKIP|db-primary-key|no SQL, Prisma, Django/SQLAlchemy, TypeORM or Drizzle schema files found"
  echo "SKIP|db-fk-index|no schema files found"
  echo "SKIP|db-unique|no schema files found"
else
  group db-primary-key "every table/model found has a primary key"
  group db-fk-index "every foreign key found is indexed"
  group db-unique "no email/username column without a unique constraint found (heuristic)"
fi
group db-migrations "migrations present"
if [ "$ISSUPA" -eq 1 ]; then group db-rls "every Supabase table found has row level security enabled"
else echo "SKIP|db-rls|not a Supabase project (no supabase/ dir or @supabase dependency)"; fi
group db-backup "backup mentioned"
exit 0
