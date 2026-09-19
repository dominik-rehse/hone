const roles = require("./roles.js");

// What the person a document belongs to may do to it, whatever role they hold.
const OWNER_ACTIONS = new Set(["view", "edit", "delete"]);

function owns(user, resource) {
  return resource.ownerId === user.id;
}

// Whether `user` may do `action` to `resource`.
function allows(user, action, resource) {
  if (!roles.isRole(user.role)) {
    return false;
  }
  if (OWNER_ACTIONS.has(action) && owns(user, resource)) {
    return true;
  }
  return roles.actionsOf(user.role).includes(action);
}

module.exports = { allows, owns, OWNER_ACTIONS };
