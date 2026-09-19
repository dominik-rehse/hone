const roles = require("./authz/roles.js");

const people = new Map();

function add({ id, name, role = "viewer" }) {
  const person = { id, name, role };
  people.set(id, person);
  return person;
}

function get(id) {
  return people.get(id) ?? null;
}

// Move one person to another role. Null for an unknown person or a role that
// is not one.
function setRole(id, role) {
  const person = get(id);
  if (person === null || !roles.isRole(role)) {
    return null;
  }
  person.role = role;
  return person;
}

function all() {
  return [...people.values()];
}

function reset() {
  people.clear();
}

module.exports = { add, get, setRole, all, reset };
