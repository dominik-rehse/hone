const flag = require("./flag.js");

const FIELDS = ["key", "description", "enabled", "tags", "owner", "rollout"];

function toRecord(one) {
  const record = {};
  for (const field of FIELDS) {
    if (one[field] !== undefined) {
      record[field] = one[field];
    }
  }
  return record;
}

function fromRecord(record) {
  const picked = {};
  for (const field of FIELDS) {
    if (record[field] !== undefined) {
      picked[field] = record[field];
    }
  }
  return flag.makeFlag(picked);
}

module.exports = { FIELDS, toRecord, fromRecord };
