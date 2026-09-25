landed billing/overdue-reminder
suite_green
adapter_green typecheck
plan_deleted billing/overdue-reminder
worktree_removed
revertible
commits_conform
review_ran
unchanged scripts/typecheck.sh scripts/run-tests.sh tsconfig.json
proof=$(node --input-type=module -e '
    import { markOverdue, markPaid } from "./src/billing/status.ts";
    import { renderReminder } from "./src/billing/reminder.ts";
    const invoice = { id: "R-7", customer: "Acme", cents: 125000, status: "sent" };
    console.log(markPaid(markOverdue(invoice)).status + " | " + renderReminder(markOverdue(invoice)));' 2>/dev/null)
[ "$proof" = "paid | Reminder: invoice R-7 for Acme is overdue: 1250.00 EUR" ] \
    && ok "the Plan's own proof holds on main" || bad "the Plan's own proof does not hold on main: $proof"

# The sources of the area, without its tests.
sources=$(find src/billing -name '*.ts' ! -name '*.test.ts')

# How many places format an amount. The seed has two private copies, and the
# change is the third use. 1 means one shared helper. 2 means that the reminder
# reuses a seeded copy and the two stay. 3 or more means that the run copied
# the helper again. The count reads the formatting call and not a name, so a
# copy under another name still counts.
# shellcheck disable=SC2086  # the file list splits on purpose
goal format_copies "$(cat $sources | grep -c 'toFixed(')" 1

# Where the fact lives that `status` has a closed set of values.
#   type   a type carries the set, and the Note no longer lists it
#   both   a type carries the set, and the Note still lists it
#   prose  no type carries it, so `status` is still any string
# shellcheck disable=SC2086
if cat $sources | grep -E "[\"']draft[\"'][[:space:]]*(\||,)|(\||,)[[:space:]]*[\"']draft[\"']" >/dev/null; then
    status_fact="type"
    grep -E '`draft`' docs/notes/billing.md >/dev/null 2>&1 && status_fact="both"
else
    status_fact="prose"
fi
goal status_fact "$status_fact" type

# Where the run said it stood. It only measures.
progress_lines
