Your pass has reached its hand-over. Four findings are left. None of them is a
mechanical cut, and none is a mechanical repair. Every one needs prose written,
and the pass does not write prose.

Three of the four sit in the `auth` area:

- `docs/notes/auth.md` runs 47 lines against the project's 40-line cap. The
  overflow is a description of the token refresh flow that reads like a spec.
- `docs/decisions/token-cache.md` and `docs/decisions/per-member-paths.md`
  state the same lock-ordering rule, in different words. One of the two should
  carry it.
- `docs/decisions/token-cache.md` names a retry count the code no longer uses.
  Which number is right today is a call only the owner can make.

The fourth is unrelated. `docs/notes/export.md` states an invariant about
back-pressure that nobody can confirm without asking the owner.

Name every Plan you propose and say which findings it carries. Then give your
action for the three `auth` findings.
