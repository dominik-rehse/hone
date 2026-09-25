#!/bin/bash
# End-to-end proof of shared mode (.hone-shared): two developers, two clones,
# one bare remote. Pins the mechanical contract: add claims a change on the
# remote and the second claimant loses, land pushes the tested merge and
# releases the claim, a push the remote rejected undoes the local fast-forward and retries,
# landed reads the remote, and sync rebases a local Plan commit onto the
# team's primary branch. Run: bash test/e2e_shared_test.sh
set -uo pipefail

PLUGIN_ROOT=$(cd "$(dirname "$0")/.." && pwd)
WSH="$PLUGIN_ROOT/scripts/worktree.sh"
step() { printf '  %s\n' "$1"; }
die()  { printf '  FAIL: %s\n' "$1"; exit 1; }

command -v node >/dev/null 2>&1 || { echo "  SKIP: node not available"; exit 0; }
command -v flock >/dev/null 2>&1 || { echo "  SKIP: flock not available"; exit 0; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ORIGIN="$TMP/origin.git"; A="$TMP/a"; B="$TMP/b"; C="$TMP/c"
git init -q --bare "$ORIGIN" && git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main

# Seed the project from clone A: a node adapter, the ephemeral ignores, and
# the shared marker. The adapter also carries the race hook used in step 4:
# with HONE_TEST_RACE set, its first run pushes a commit from a third clone,
# which is "another developer landed while this suite ran".
git clone -q "$ORIGIN" "$A" 2>/dev/null
git -C "$A" symbolic-ref HEAD refs/heads/main
for r in "$A"; do git -C "$r" config user.email a@t.t; git -C "$r" config user.name a; done
mkdir -p "$A/src/mathx" "$A/scripts"
printf '.worktrees/\n.hone-grant/\n.hone-proof/\n' > "$A/.gitignore"
cat > "$A/scripts/run-tests.sh" <<'EOF'
#!/bin/bash
case "${1:-}" in --all|--unit) shift ;; esac
if [ -n "${HONE_TEST_RACE:-}" ] && [ ! -e "$HONE_TEST_RACE/done" ]; then
  : > "$HONE_TEST_RACE/done"
  ( cd "$HONE_TEST_RACE/clone" && git pull -q --ff-only \
    && echo x >> RACE.md && git add RACE.md \
    && git commit -qm "race: another developer landed" && git push -q ) || exit 1
fi
node -e '
  const fs = require("fs");
  for (const f of fs.readdirSync("src/mathx").filter(f => f.endsWith(".test.js")))
    require("./src/mathx/" + f);
  console.log("ok");
' 2>/dev/null
EOF
chmod +x "$A/scripts/run-tests.sh"
echo "# seed" > "$A/README.md"
printf '# shared mode: the remote the team lands on (blank means origin)\n' > "$A/.hone-shared"
mkdir -p "$A/src/mathx"; echo '// seed' > "$A/src/mathx/seed.test.js"
git -C "$A" add -A && git -C "$A" commit -qm "seed: project skeleton" && git -C "$A" push -q -u origin main 2>/dev/null

git clone -q "$ORIGIN" "$B" 2>/dev/null; git -C "$B" config user.email b@t.t; git -C "$B" config user.name b
git clone -q "$ORIGIN" "$C" 2>/dev/null; git -C "$C" config user.email c@t.t; git -C "$C" config user.name c

# A change with a real test, written straight into a worktree (the guard's
# test-first rule is pinned by e2e_land_test.sh, not here).
write_change() {   # <worktree> <name>
    cat > "$1/src/mathx/$2.test.js" <<EOF
const {$2} = require("./$2.js");
if ($2(2,3) !== 5) throw new Error("$2 broken");
EOF
    printf 'exports.%s = (a, b) => a + b;\n' "$2" > "$1/src/mathx/$2.js"
    (cd "$1" && git add -A && git commit -qm "feat(mathx): $2()" -m "Cut: nothing, a test change") || die "commit $2"
}
# Capture the log, then grep the string. A `git log | grep -q` under pipefail
# reads as failed whenever grep quits before git finishes writing (SIGPIPE),
# which is the flake cmd_landed's comment describes.
log_has() {   # <repo> <ref-or-limit...> <pattern>
    local repo="$1"; shift
    local pattern="${*: -1}"; set -- "${@:1:$#-1}"
    local out; out=$(git -C "$repo" log --format=%s "$@" 2>/dev/null)
    printf '%s\n' "$out" | grep -qF -- "$pattern"
}
remote_has_claim() { git -C "$ORIGIN" show-ref --verify --quiet "refs/hone/claim/$1"; }
origin_main() { git -C "$ORIGIN" rev-parse refs/heads/main; }

echo "== 1. add claims the change on the remote =="
WTA=$(cd "$A" && bash "$WSH" add x) || die "A: add x"
remote_has_claim x && step "origin holds a claim on x after A's add" || die "A's add did not push the claim"
out=$(cd "$B" && bash "$WSH" add x 2>&1); rc=$?
[ "$rc" -eq 4 ] && step "B: add x exits 4 (claimed)" || die "B: add x exited $rc, expected 4: $out"
echo "$out" | grep -q 'origin already holds a claim on x' || die "B: wrong message: $out"
[ -e "$B/.worktrees/x" ] && die "B: worktree left behind after a refused claim"
git -C "$B" show-ref --verify --quiet refs/heads/hone/x && die "B: branch left behind after a refused claim"
step "B: refused claim leaves no worktree and no branch"

echo "== 2. status shows the shared remote and the other developer's claim =="
out=$(cd "$B" && bash "$WSH" status)
echo "$out" | grep -q 'shared: .hone-shared present (committed), land pushes to origin' || die "status lacks the shared line: $out"
echo "$out" | grep -q 'claimed on origin: x by a <a@t.t> on' || die "status lacks A's claim: $out"
step "status names the remote and A's claim on x"

echo "== 3. land pushes the tested merge and releases the claim =="
write_change "$WTA" x
before=$(origin_main)
out=$(cd "$A" && bash "$WSH" land x 2>&1) || die "A: land x: $out"
echo "$out" | grep -q 'land pushed main to origin' || die "A: receipt lacks the push line: $out"
[ "$(origin_main)" != "$before" ] || die "origin/main did not move"
log_has "$ORIGIN" -n 1 main "Merge branch 'hone/x'" || die "merge commit not on origin/main"
remote_has_claim x && die "claim on x still on origin after land" || step "landed on origin, claim released"
out=$(cd "$B" && bash "$WSH" landed x); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = landed ] && step "B: landed x reads the remote" || die "B: landed x -> $rc $out"
[ "$(git -C "$B" rev-parse HEAD)" != "$(origin_main)" ] || die "B's main should still be behind here"
out=$(cd "$B" && bash "$WSH" sync) || die "B: sync: $out"
[ "$(git -C "$B" rev-parse HEAD)" = "$(origin_main)" ] && step "B: sync fast-forwarded main" || die "B: sync did not level main"

echo "== 4. a push the remote rejects undoes the fast-forward and retries =="
WTB=$(cd "$B" && bash "$WSH" add y) || die "B: add y"
write_change "$WTB" y
RACE="$TMP/race"; mkdir -p "$RACE"; ln -s "$C" "$RACE/clone"
out=$(cd "$B" && HONE_TEST_RACE="$RACE" bash "$WSH" land y 2>&1) || die "B: land y: $out"
echo "$out" | grep -q 'origin/main moved, so land undoes its fast-forward and retries (attempt 2)' || die "no retry line: $out"
log_has "$ORIGIN" main 'race: another developer landed' || die "C's commit missing on origin"
log_has "$ORIGIN" -n 1 main "Merge branch 'hone/y'" || die "y's merge not on top of origin/main"
[ "$(git -C "$B" rev-parse HEAD)" = "$(origin_main)" ] || die "B's main != origin/main after the retry"
git -C "$B" merge-base --is-ancestor "$(git -C "$C" rev-parse HEAD)" HEAD || die "the merge was not rebuilt on C's commit"
[ -d "$WTB" ] && die "worktree still present after land" || step "retried once, landed on top of C's commit"

echo "== 5. retries exhausted: nothing published, worktree kept, exit 5 =="
WTB=$(cd "$B" && bash "$WSH" add v) || die "B: add v"
write_change "$WTB" v
rm -f "$RACE/done"; pre=$(git -C "$B" rev-parse HEAD)
out=$(cd "$B" && HONE_TEST_RACE="$RACE" HONE_LAND_RETRIES=1 bash "$WSH" land v 2>&1); rc=$?
[ "$rc" -eq 5 ] || die "expected exit 5, got $rc: $out"
echo "$out" | grep -q 'moved during each of 1 land attempts' || die "wrong message: $out"
[ "$(git -C "$B" rev-parse HEAD)" = "$pre" ] || die "primary tree moved after the unpublished land"
[ -d "$WTB" ] && remote_has_claim v && step "nothing published, worktree and claim kept" || die "evidence lost"
log_has "$ORIGIN" main "Merge branch 'hone/v'" && die "untested merge reached origin"
out=$(cd "$B" && bash "$WSH" remove "$WTB" 2>&1) || die "B: remove v: $out"
remote_has_claim v && die "remove left the claim on origin" || step "remove released the claim"
git -C "$B" branch -D hone/v -q

echo "== 5b. a refused push (protected branch) is exit 2, not a retry =="
WTB=$(cd "$B" && bash "$WSH" add u) || die "B: add u"
write_change "$WTB" u
printf '#!/bin/bash\nwhile read o n r; do [ "$r" = refs/heads/main ] && { echo "main is protected" >&2; exit 1; }; done; exit 0\n' > "$ORIGIN/hooks/pre-receive"
chmod +x "$ORIGIN/hooks/pre-receive"
pre=$(git -C "$B" rev-parse HEAD)
out=$(cd "$B" && bash "$WSH" land u 2>&1); rc=$?
[ "$rc" -eq 2 ] || die "expected exit 2 on a refused push, got $rc: $out"
echo "$out" | grep -q 'origin refused the push to main, and origin/main did not move' || die "wrong message: $out"
echo "$out" | grep -q 'main is protected' || die "the host's reason is missing from the paste block: $out"
echo "$out" | grep -q 'retries' && die "a refused push must not retry"
[ "$(git -C "$B" rev-parse HEAD)" = "$pre" ] || die "primary tree moved after the refused land"
[ -d "$WTB" ] && remote_has_claim u && step "refused push: exit 2, fast-forward undone, evidence kept" || die "evidence lost"
rm -f "$ORIGIN/hooks/pre-receive"
(cd "$B" && bash "$WSH" remove "$WTB" >/dev/null 2>&1) && git -C "$B" branch -D hone/u -q
echo "== 5c. release by hand =="
(cd "$B" && bash "$WSH" add t >/dev/null) || die "B: add t"
rm -rf "$B/.worktrees/t"; git -C "$B" worktree prune; git -C "$B" branch -D hone/t -q
remote_has_claim t || die "setup: claim t missing"
out=$(cd "$B" && bash "$WSH" release t) || die "release t: $out"
remote_has_claim t && die "release left the claim" || step "release removed the claim"

echo "== 6. a local Plan commit rebases onto the team's main at add =="
mkdir -p "$B/.plans"; echo "# z" > "$B/.plans/z.md"
(cd "$B" && git add .plans/z.md && git commit -qm "chore(plan): z") || die "B: plan commit"
WTA=$(cd "$A" && bash "$WSH" add w) || die "A: add w"
write_change "$WTA" w
(cd "$A" && bash "$WSH" land w >/dev/null 2>&1) || die "A: land w"
WTB=$(cd "$B" && bash "$WSH" add z) || die "B: add z after divergence"
git -C "$ORIGIN" cat-file -e main:.plans/z.md 2>/dev/null || die "Plan z not on origin/main after add"
git -C "$B" merge-base --is-ancestor "$(origin_main)" HEAD || die "B's main not level with origin"
log_has "$B" -n 3 main "Merge branch 'hone/w'" || die "A's merge missing from B's main"
step "Plan commit rebased and pushed, worktree cut from the team's main"
write_change "$WTB" z
(cd "$WTB" && git rm -q .plans/z.md && git commit -qm "chore: consolidate z" -m "Cut: nothing, a test change") || die "consolidate z"
(cd "$B" && bash "$WSH" land z >/dev/null 2>&1) || die "B: land z"
git -C "$ORIGIN" cat-file -e main:.plans/z.md 2>/dev/null && die "Plan z survived its land"
out=$(cd "$A" && bash "$WSH" landed z) && [ "$out" = landed ] && step "A: landed z" || die "A: landed z -> $out"

echo "== 7. sync refuses a dirty primary tree and reports a missing remote =="
echo dirty >> "$B/README.md"
(cd "$C" && git pull -q --ff-only && echo m >> README.md && git commit -qam "c: move main" && git push -q)
out=$(cd "$B" && bash "$WSH" sync 2>&1); rc=$?
[ "$rc" -eq 2 ] && echo "$out" | grep -q 'uncommitted changes' && step "dirty primary refused" || die "dirty: $rc $out"
git -C "$B" checkout -q -- README.md
printf 'nowhere\n' > "$B/.hone-shared"
out=$(cd "$B" && bash "$WSH" sync 2>&1); rc=$?
[ "$rc" -eq 2 ] && echo "$out" | grep -q 'no such remote' && step "missing remote refused" || die "no-remote: $rc $out"
git -C "$B" checkout -q -- .hone-shared

echo "e2e_shared_test: all steps passed"
