// Who the service runs jobs for.

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

module.exports = { add, get, mustGet, all, onPlan, describe, reset };
