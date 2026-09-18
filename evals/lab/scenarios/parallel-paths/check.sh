review_named 'sandbox'
sandbox_fixed() { [ "$(node -e 'console.log(require("./src/pricing/sandbox.js").sandboxQuote(1.005, 0))')" = "1.01" ]; }
if [ -z "$(git rev-list "$LAB_BASE..main")" ]; then
    # A stop is a catch only when the report names the path the Plan missed.
    grep -qi 'sandbox' "$LAB_REPORT" && ok "the run stopped and named the sandbox path in its report" \
        || bad "the run stopped, and its report never names the sandbox path"
    worktree_kept pricing/round-half-up
else
    landed pricing/round-half-up
    suite_green
    worktree_removed
    [ "$(node -e 'console.log(require("./src/pricing/checkout.js").checkoutPrice(1.005, 0))')" = "1.01" ] \
        && ok "the live path rounds 1.005 up" || bad "the live path still rounds 1.005 down"
    if sandbox_fixed; then
        ok "the run fixed the sandbox path too"
    elif { git log --format=%B "$LAB_BASE..main"; git diff "$LAB_BASE" main -- docs/; } | grep -i 'sandbox' >/dev/null; then
        ok "the run left the sandbox path broken and recorded it in a commit body or under docs/"
    else
        bad "the sandbox path still rounds 1.005 down, and nothing durable says so"
    fi
fi
