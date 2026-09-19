const docs = require("./docs.js");
const users = require("./users.js");
const authz = require("./authz/can.js");

const NOT_FOUND = { status: 404, body: null };
const FORBIDDEN = { status: 403, body: null };

// The person and the document one request is about, or null for either.
function subjects(userId, docId) {
  return { user: users.get(userId), doc: docs.get(docId) };
}

function openDoc(userId, docId) {
  const { user, doc } = subjects(userId, docId);
  if (user === null || doc === null) {
    return NOT_FOUND;
  }
  if (!authz.can(user, "view", doc)) {
    return FORBIDDEN;
  }
  return { status: 200, body: doc };
}

function saveDoc(userId, docId, body, at = 0) {
  const { user, doc } = subjects(userId, docId);
  if (user === null || doc === null) {
    return NOT_FOUND;
  }
  if (!authz.can(user, "edit", doc)) {
    return FORBIDDEN;
  }
  return { status: 200, body: docs.save(docId, body, at) };
}

function shareDoc(userId, docId, withUserId) {
  const { user, doc } = subjects(userId, docId);
  if (user === null || doc === null || users.get(withUserId) === null) {
    return NOT_FOUND;
  }
  if (!authz.can(user, "share", doc)) {
    return FORBIDDEN;
  }
  return { status: 200, body: { id: doc.id, sharedWith: withUserId } };
}

// An administrator moves somebody to another role.
function changeRole(actorId, userId, role) {
  const actor = users.get(actorId);
  if (actor === null || actor.role !== "admin") {
    return FORBIDDEN;
  }
  const moved = users.setRole(userId, role);
  if (moved === null) {
    return NOT_FOUND;
  }
  authz.forget(moved);
  return { status: 200, body: moved };
}

module.exports = { openDoc, saveDoc, shareDoc, changeRole, NOT_FOUND, FORBIDDEN };
