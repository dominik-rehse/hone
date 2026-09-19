// The settings the service runs with. The deployment writes over them from the
// environment file at boot, and nothing writes over them after that.
const DEFAULTS = {
  cookieName: "sid",
  secureCookie: true,
  sessionTtl: 1800,
  sweepBatch: 100,
  loginAttempts: 5,
};

const NUMBERS = new Set(["sessionTtl", "sweepBatch", "loginAttempts"]);

let settings = { ...DEFAULTS };

// Keep the settings we know and drop the rest. A number that is not one, or is
// not above zero, keeps its default.
function clean(overrides) {
  const kept = {};
  for (const [name, value] of Object.entries(overrides)) {
    if (!(name in DEFAULTS)) {
      continue;
    }
    if (NUMBERS.has(name) && (typeof value !== "number" || !(value > 0))) {
      continue;
    }
    kept[name] = value;
  }
  return kept;
}

function load(overrides = {}) {
  settings = { ...DEFAULTS, ...clean(overrides) };
  return settings;
}

function current() {
  return settings;
}

function reset() {
  settings = { ...DEFAULTS };
  return settings;
}

module.exports = { load, current, reset, DEFAULTS };
