const roles = require("./roles.js");

// Whether `user` may do `action`.
function allows(user, action) {
  if (!roles.isRole(user.role)) {
    return false;
  }
  return roles.actionsOf(user.role).includes(action);
}

module.exports = { allows };
