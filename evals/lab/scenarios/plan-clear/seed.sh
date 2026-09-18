# The price of a Plan in human attention. The sketch below is complete: it
# names the behaviour, the reason, and three checkable proofs, and it leaves no
# fork open. A session of /hone:plan must write the Plan, get it through the
# plan-critic, and commit it. Every round of the critic beyond the first is
# attention that a person would have paid, so the scenario counts the rounds.
mkdir -p src/text docs/notes
cat > src/text/slugify.js <<'JS'
// A URL slug from a post title.
function slugify(title) {
  return title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

module.exports = { slugify };
JS
cat > src/text/slugify.test.js <<'JS'
const test = require("node:test");
const assert = require("node:assert");
const { slugify } = require("./slugify.js");

test("lowercases and joins the words with one dash", () => {
  assert.strictEqual(slugify("Hello, World!"), "hello-world");
  assert.strictEqual(slugify("  --A  b--"), "a-b");
});

test("gives the empty string for a title with no letter and no digit", () => {
  assert.strictEqual(slugify("!!!"), "");
});
JS
cat > docs/notes/text.md <<'MD'
# text

Governs: `src/text/`

Map: one pure function per file, each with its tests beside it.

Invariant: no function in this area reads the clock, the locale, or the disk.
MD
