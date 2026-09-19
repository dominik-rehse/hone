// The roles a workspace member can hold, weakest first.
const ORDER = ["guest", "viewer", "editor", "admin"];

// What each role may do, whoever the document belongs to.
const ACTIONS = {
  guest: [],
  viewer: ["view"],
  editor: ["view", "edit"],
  admin: ["view", "edit", "delete", "share"],
};

function isRole(name) {
  return ORDER.includes(name);
}

// Where a role sits in the order. -1 for a name that is not a role.
function rank(name) {
  return ORDER.indexOf(name);
}

function actionsOf(name) {
  return ACTIONS[name] ?? [];
}

// Is `name` the same role as `other`, or a stronger one?
function atLeast(name, other) {
  return isRole(name) && isRole(other) && rank(name) >= rank(other);
}

module.exports = { ORDER, ACTIONS, isRole, rank, actionsOf, atLeast };
