plan=.plans/text/truncate.md
[ -n "$(git log --format=%h "$LAB_BASE..main" -- "$plan")" ] && ok "the Plan is committed on main" || bad "no commit on main carries $plan"
[ -z "$(git status --porcelain -- .plans)" ] && ok "nothing under .plans/ is left uncommitted" || bad ".plans/ holds uncommitted work"
grep -E '^## What' "$plan" >/dev/null 2>&1 && grep -E '^## Why' "$plan" >/dev/null 2>&1 && grep -E "^## How I'll know it works" "$plan" >/dev/null 2>&1 \
    && ok "the Plan has its three sections" || bad "the Plan lacks What, Why, or How I'll know it works"
grep -F 'Hellowo…' "$plan" >/dev/null 2>&1 && ok "the Plan carries the proof of the sketch" || bad "the Plan lost the proof that the sketch gave"
# /hone:plan writes a Plan and nothing else. A spike note and an open
# question are the two other things that it may write.
diff_confined '^(\.plans/|docs/spikes/|docs/open-questions\.md$)'
worktree_removed
reviewed_once
# Each call of the plan-critic is one round. A round beyond the first means
# that the critic sent a complete sketch back.
rounds=$(agent_calls 'plan-critic')
[ "$rounds" -ge 1 ] && ok "the plan-critic read the Plan" || bad "no call of the plan-critic is in the transcript"
measure critic_rounds "$rounds"
goal bounced "$([ "$rounds" -gt 1 ] && echo yes || echo no)" no
