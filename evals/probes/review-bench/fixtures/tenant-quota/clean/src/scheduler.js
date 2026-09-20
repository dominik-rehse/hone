const queue = require("./queue.js");
const jobs = require("./jobs.js");
const tenants = require("./tenants.js");
const metrics = require("./metrics.js");
const quota = require("./quota.js");

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
  quota.rollWindow();
  const limit = tenants.limitFor(tenant);
  const used = quota.count(tenantId) + 1;
  if (used > limit) {
    metrics.inc("submit.over-quota");
    return { accepted: false, reason: "over-quota", used, limit };
  }
  job.priority = tenants.priorityFor(tenant);
  if (!queue.push(job)) {
    metrics.inc("submit.queue-full");
    return { accepted: false, reason: "queue-full" };
  }
  quota.record(tenantId);
  metrics.inc("submit.accepted");
  return { accepted: true, id: job.id, used, limit };
}

// How many jobs the tenant has left in the window that is open.
function remaining(tenantId) {
  const tenant = tenants.mustGet(tenantId);
  quota.rollWindow();
  return quota.remaining(tenantId, tenants.limitFor(tenant));
}

// What the status endpoint answers.
function status() {
  quota.rollWindow();
  return {
    pending: queue.size(),
    capacity: queue.getCapacity(),
    tenants: tenants.all().length,
    quota: quota.snapshot(),
  };
}

module.exports = { submit, remaining, status };
