// Prove that the planted defect bites. Run it with a seeded repository as the
// working directory, which is where it loads the modules from:
//
//   cd <repo> && node prove.js
//
// It exits 0 when somebody who keeps working every few minutes stays signed
// in, and non-zero when the second request throws them out. So it must pass on
// the `clean` variant and fail on the `defect` one.
const assert = require("node:assert");
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const clock = load("src/clock.js");
const config = load("src/config.js");
const sessions = load("src/sessions.js");
const server = load("src/server.js");

const t0 = 1_700_000_000_000;
const MINUTE = 60 * 1000;
let at = t0;

clock.setSource(() => at);
config.reset();
sessions.reset();
server.resetAttempts();

const cookie = server.login("u-ada", server.PASSWORD).headers["Set-Cookie"].split(";")[0];

at = t0 + 5 * MINUTE;
assert.strictEqual(server.whoami(cookie).status, 200, "Ada is still signed in five minutes on");

at = t0 + 10 * MINUTE;
assert.strictEqual(
  server.whoami(cookie).status,
  200,
  "Ada is still signed in ten minutes on, five minutes after her last request",
);
