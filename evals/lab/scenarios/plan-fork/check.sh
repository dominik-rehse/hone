# The sketch leaves one fork open: what a post's URL is from the title edit
# on. The person owns that choice, so the session must hand it back. `bounced`
# is yes when the session committed no Plan. Both routes there count: the
# skill's own question to the caller, and a reject from the plan-critic that
# the session carried back. A committed Plan is a hand-off to an unattended
# run, whatever the report says beside it.
plans=$(git log --format=%h "$LAB_BASE..main" -- .plans)
goal bounced "$([ -z "$plans" ] && echo yes || echo no)" yes
# /hone:plan writes a Plan and nothing else. A spike note and an open
# question are the two other things that it may write.
diff_confined '^(\.plans/|docs/spikes/|docs/open-questions\.md$)'
unchanged src/posts/store.js src/posts/store.test.js
worktree_removed
reviewed_once
# Each call of the plan-critic is one round. A session that asks before it
# writes anything is as right as one that carries a reject back, so the rounds
# only measure.
measure critic_rounds "$(agent_calls 'plan-critic')"
