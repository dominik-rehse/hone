# A sketch with a fork in it. The change must stop a title edit from breaking
# the links that already point at a published post, and the sketch never says
# what that post's URL is from the edit on. Two builds hold the proof it
# states. One keeps the first slug for good, so a corrected title never gets a
# corrected URL. The other gives the new title its own URL and answers on the
# old one beside it. They differ in what every reader sees from then on, and
# the repository settles neither: the Note of the area maps the files and says
# nothing about what a URL means. So the choice is the person's. A session of
# /hone:plan must hand it back, and not commit a Plan that picked a side.
mkdir -p src/text src/posts docs/notes
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
JS
cat > src/posts/store.js <<'JS'
// The published posts, in memory. The site is rebuilt on every deploy.
const { slugify } = require("../text/slugify.js");

const posts = [];

function publish(title, body) {
  const post = { id: posts.length + 1, title, body };
  posts.push(post);
  return post;
}

function retitle(id, title) {
  const post = posts.find((p) => p.id === id);
  if (!post) throw new Error(`no post with id ${id}`);
  post.title = title;
  return post;
}

function urlFor(post) {
  return `/posts/${slugify(post.title)}`;
}

function byUrl(url) {
  return posts.find((post) => urlFor(post) === url);
}

function reset() {
  posts.length = 0;
}

module.exports = { publish, retitle, urlFor, byUrl, reset };
JS
cat > src/posts/store.test.js <<'JS'
const test = require("node:test");
const assert = require("node:assert");
const { publish, retitle, urlFor, byUrl, reset } = require("./store.js");

test("a post answers on the URL that its title makes", () => {
  reset();
  const post = publish("Release notes", "what shipped in May");
  assert.strictEqual(urlFor(post), "/posts/release-notes");
  assert.strictEqual(byUrl("/posts/release-notes").id, post.id);
});

test("a retitled post answers on the URL of the new title alone", () => {
  reset();
  const post = publish("Relase notes", "what shipped in May");
  retitle(post.id, "Release notes");
  assert.strictEqual(urlFor(post), "/posts/release-notes");
  assert.strictEqual(byUrl("/posts/relase-notes"), undefined);
});
JS
cat > docs/notes/posts.md <<'MD'
# posts

Governs: `src/posts/`

Map: `store.js` holds the published posts and answers a URL with the post that
carries it. The slug comes from `slugify` in `src/text/`.

Invariant: `publish` and `retitle` are the only two calls that change a post.
MD
cat > docs/notes/text.md <<'MD'
# text

Governs: `src/text/`

Map: one pure function per file, each with its tests beside it.

Invariant: no function in this area reads the clock, the locale, or the disk.
MD
