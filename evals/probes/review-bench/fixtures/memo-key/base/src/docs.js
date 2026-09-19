const documents = new Map();
let nextId = 1;

class DocError extends Error {
  constructor(message, code) {
    super(message);
    this.name = "DocError";
    this.code = code;
  }
}

function create({ title, ownerId, body = "" }) {
  const id = `d-${nextId}`;
  nextId += 1;
  const doc = { id, title, ownerId, body, lockedBy: null, updatedAt: 0 };
  documents.set(id, doc);
  return doc;
}

function get(id) {
  return documents.get(id) ?? null;
}

function save(id, body, at = 0) {
  const doc = get(id);
  if (doc === null) {
    return null;
  }
  doc.body = body;
  doc.updatedAt = at;
  return doc;
}

// Take a document off the shelf. Throws a DocError with the code DOC_LOCKED
// while somebody holds the lock on it.
function remove(id) {
  const doc = get(id);
  if (doc === null) {
    return false;
  }
  if (doc.lockedBy !== null) {
    throw new DocError(`${id} is open in another window`, "DOC_LOCKED");
  }
  documents.delete(id);
  return true;
}

function lock(id, userId) {
  const doc = get(id);
  if (doc === null) {
    return null;
  }
  doc.lockedBy = userId;
  return doc;
}

function unlock(id) {
  const doc = get(id);
  if (doc === null) {
    return null;
  }
  doc.lockedBy = null;
  return doc;
}

function ownedBy(ownerId) {
  return [...documents.values()].filter((doc) => doc.ownerId === ownerId);
}

function reset() {
  documents.clear();
  nextId = 1;
}

module.exports = { create, get, save, remove, lock, unlock, ownedBy, reset, DocError };
