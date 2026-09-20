const hash = require("./hash.js");

// A rollout puts a flag on for a share of the callers rather than for all of
// them. The share is a whole percentage and the buckets are a hundred wide.
const BUCKETS = 100;

function isPercent(value) {
  return Number.isInteger(value) && value >= 0 && value <= 100;
}

// The bucket a caller falls in for one flag. The same pair always lands in
// the same bucket, so a caller who is inside a rollout stays inside it while
// the percentage holds.
function bucketFor(userId, flagKey) {
  return hash.hash32(hash.keyOf(userId, flagKey)) % BUCKETS;
}

// Whether this caller is inside a rollout of `percent` on this flag.
function inRollout(userId, flagKey, percent) {
  if (!isPercent(percent)) {
    return false;
  }
  if (percent <= 0) {
    return false;
  }
  if (percent >= 100) {
    return true;
  }
  if (typeof userId !== "string" || userId === "") {
    return false;
  }
  return bucketFor(userId, flagKey) < percent;
}

// The two halves a rollout would cut a list of callers into, for the preview
// the admin screen shows before the percentage goes in.
function split(userIds, flagKey, percent) {
  const inside = [];
  const outside = [];
  for (const userId of userIds) {
    (inRollout(userId, flagKey, percent) ? inside : outside).push(userId);
  }
  return { inside, outside };
}

// The rollout a flag carries, or null for a flag that is on for everyone.
function of(one) {
  return one.rollout == null ? null : one.rollout;
}

function describe(one) {
  const rollout = of(one);
  return rollout === null ? "all" : `${rollout.percent}%`;
}

module.exports = { BUCKETS, isPercent, bucketFor, inRollout, split, of, describe };
