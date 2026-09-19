// Work that the service runs again when it goes wrong.

// Run `work`. When it throws, run it again, up to `attempts` times in all, and
// throw the last error when none of the attempts got through.
function withRetry(work, { attempts = 3, onAttempt = () => {} } = {}) {
  let last = null;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    onAttempt(attempt);
    try {
      return work();
    } catch (error) {
      last = error;
    }
  }
  throw last;
}

module.exports = { withRetry };
