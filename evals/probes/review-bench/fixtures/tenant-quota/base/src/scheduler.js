const queue = require("./queue.js");
const jobs = require("./jobs.js");
const tenants = require("./tenants.js");
const metrics = require("./metrics.js");

// Put a job on the queue for a tenant. Every answer names why, so the API can
// hand the caller something to read.
function submit(tenantId, kind, payload = {}) {
  const tenant = tenants.get(tenantId);
  if (tenant == null) {
    metrics.inc("submit.unknown-tenant");
    return { accepted: false, reason: "unknown-tenant" };
  }
  let job;
  try {
    job = jobs.make({ tenantId, kind, payload });
  } catch (err) {
    if (!(err instanceof RangeError)) {
      throw err;
    }
    metrics.inc("submit.bad-kind");
    return { accepted: false, reason: "bad-kind" };
  }
  if (!queue.push(job)) {
    metrics.inc("submit.queue-full");
    return { accepted: false, reason: "queue-full" };
  }
  metrics.inc("submit.accepted");
  return { accepted: true, id: job.id };
}

// What the status endpoint answers.
function status() {
  return {
    pending: queue.size(),
    capacity: queue.getCapacity(),
    tenants: tenants.all().length,
  };
}

module.exports = { submit, status };
