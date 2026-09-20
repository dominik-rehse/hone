// A job as the queue carries it.

const KINDS = ["email", "report", "export"];

let nextId = 1;

function make({ tenantId, kind, payload = {} }) {
  if (typeof tenantId !== "string" || tenantId.trim() === "") {
    throw new TypeError("a job needs a tenant");
  }
  if (!KINDS.includes(kind)) {
    throw new RangeError(`unknown job kind: ${kind}`);
  }
  return {
    id: `job-${nextId++}`,
    tenantId: tenantId.trim(),
    kind,
    payload,
    at: Date.now(),
  };
}

function describe(job) {
  return `${job.id} ${job.kind} for ${job.tenantId}`;
}

function isKind(kind) {
  return KINDS.includes(kind);
}

function resetIds() {
  nextId = 1;
}

module.exports = { KINDS, make, describe, isKind, resetIds };
