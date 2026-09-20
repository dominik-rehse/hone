// Who the service runs jobs for.

// What a plan buys: how many jobs a tenant may put in per window, and where
// its jobs sit in the queue against another tenant's.
const PLANS = {
  free: { limit: 5, priority: 0 },
  trial: { limit: 20, priority: 5 },
  paid: { limit: 200, priority: 10 },
};

const tenants = new Map();

function add({ id, name = "", plan = "free" }) {
  if (typeof id !== "string" || id.trim() === "") {
    throw new TypeError("a tenant needs an id");
  }
  const tenant = { id: id.trim(), name, plan };
  tenants.set(tenant.id, tenant);
  return tenant;
}

function get(id) {
  return tenants.has(id) ? tenants.get(id) : null;
}

function mustGet(id) {
  const tenant = get(id);
  if (tenant === null) {
    throw new RangeError(`no such tenant: ${id}`);
  }
  return tenant;
}

// The plan a tenant is on. A plan the table does not carry reads as free.
function planOf(tenant) {
  return Object.hasOwn(PLANS, tenant.plan) ? PLANS[tenant.plan] : PLANS.free;
}

function limitFor(tenant) {
  return planOf(tenant).limit;
}

function priorityFor(tenant) {
  return planOf(tenant).priority;
}

function all() {
  return [...tenants.keys()].sort().map((id) => tenants.get(id));
}

function onPlan(plan) {
  return all().filter((tenant) => tenant.plan === plan);
}

function describe(tenant) {
  return `${tenant.id} (${tenant.plan})`;
}

function reset() {
  tenants.clear();
}

module.exports = {
  PLANS,
  add,
  get,
  mustGet,
  planOf,
  limitFor,
  priorityFor,
  all,
  onPlan,
  describe,
  reset,
};
