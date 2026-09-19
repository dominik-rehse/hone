const SEP = ":";

// The key one decision is filed under.
function memoKey(user, action, resource) {
  return `${user.id}${SEP}${action}${SEP}${resource.id}`;
}

// What every key of one person starts with.
function userPrefix(user) {
  return `${user.id}${SEP}`;
}

module.exports = { memoKey, userPrefix, SEP };
