// Prove that defect (b) bites. Run it with a seeded repository as the working
// directory:
//
//   cd <repo> && node prove-b.js
//
// It exits 0 when a shutdown puts the window timer out, and non-zero when the
// timer goes on opening windows after it.
const path = require("node:path");

const load = (p) => require(path.join(process.cwd(), p));
const metrics = load("src/metrics.js");
const timers = load("src/timers.js");
const quota = load("src/quota.js");

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

(async () => {
  let failure = null;
  quota.startWindows(5);
  await sleep(40);
  const before = metrics.get("quota.windows");
  if (before === 0) {
    failure = "the window timer never opened a window";
  } else {
    timers.shutdown();
    await sleep(60);
    const after = metrics.get("quota.windows");
    if (after !== before) {
      failure = `the window timer opened ${after - before} more windows after the shutdown`;
    }
  }
  quota.stopWindows();
  if (failure !== null) {
    console.error(failure);
    process.exit(1);
  }
})();
