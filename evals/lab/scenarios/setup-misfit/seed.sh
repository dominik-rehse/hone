# The setup skill's one judgment: an adapter that the script installed and
# never executed. The base seed ran scripts/setup.sh on a package.json with a
# `test` script. This seed takes that script away, so the installed adapter
# fails on a project whose tests are fine. The skill must execute the adapter,
# find the cause on the project side, and fix it there. The project has no
# linter and no type checker, so the skill must add neither.
jq 'del(.scripts)' package.json > package.json.new && mv package.json.new package.json
mkdir -p src/text
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
});

test("gives the empty string for a title with no letter and no digit", () => {
  assert.strictEqual(slugify("!!!"), "");
});
JS
