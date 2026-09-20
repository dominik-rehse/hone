const store = require("./store.js");
const serializer = require("./serializer.js");

const VERSION = 1;

// The whole flag list as one string, for the nightly backup.
function save() {
  return JSON.stringify({
    version: VERSION,
    flags: store.all().map(serializer.toRecord),
  });
}

// Read a saved list back. The list that was there is replaced.
function restore(text) {
  const parsed = JSON.parse(text);
  if (parsed.version !== VERSION) {
    throw new RangeError(`unknown save version: ${parsed.version}`);
  }
  store.reset();
  for (const record of parsed.flags) {
    store.put(serializer.fromRecord(record));
  }
  return store.size();
}

module.exports = { VERSION, save, restore };
