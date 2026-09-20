const jobs = require("./jobs.js");
const queue = require("./queue.js");
const metrics = require("./metrics.js");

// The webhook the first version of the service shipped with. Two customers
// still post to it and neither will move this year, so it stays.
function acceptWebhook(payload) {
  if (typeof payload !== "object" || payload === null) {
    metrics.inc("intake.bad-body");
    return { accepted: false, reason: "bad-body" };
  }
  let job;
  try {
    job = jobs.make({
      tenantId: payload.tenant,
      kind: payload.kind,
      payload: payload.body ?? {},
    });
  } catch (err) {
    if (!(err instanceof RangeError) && !(err instanceof TypeError)) {
      throw err;
    }
    metrics.inc("intake.bad-job");
    return { accepted: false, reason: "bad-job" };
  }
  if (!queue.push(job)) {
    metrics.inc("intake.queue-full");
    return { accepted: false, reason: "queue-full" };
  }
  metrics.inc("intake.accepted");
  return { accepted: true, id: job.id };
}

// What the webhook answers a caller that asks how it is doing.
function health() {
  return {
    accepted: metrics.get("intake.accepted"),
    refused:
      metrics.get("intake.bad-body") +
      metrics.get("intake.bad-job") +
      metrics.get("intake.queue-full"),
  };
}

module.exports = { acceptWebhook, health };
