const SEP = ":";

// The key one decision is filed under.
function memoKey(user, action) {
  return `${user.id}${SEP}${action}`;
}

// What every key of one person starts with.
function userPrefix(user) {
  return `${user.id}${SEP}`;
}

module.exports = { memoKey, userPrefix, SEP };
