const test = require("node:test");
const assert = require("node:assert");
const tenants = require("../../src/tenants.js");

test.beforeEach(() => tenants.reset());

test("puts a tenant on the list with the free plan", () => {
  const tenant = tenants.add({ id: "acme", name: "Acme" });
  assert.strictEqual(tenant.plan, "free");
  assert.strictEqual(tenants.get("acme").name, "Acme");
});

test("gives null for a tenant it does not carry", () => {
  assert.strictEqual(tenants.get("nobody"), null);
  assert.throws(() => tenants.mustGet("nobody"), RangeError);
});

test("refuses a tenant with no id", () => {
  assert.throws(() => tenants.add({ name: "Acme" }), TypeError);
});

test("lists its tenants in order and by plan", () => {
  tenants.add({ id: "zeta", plan: "paid" });
  tenants.add({ id: "acme" });
  tenants.add({ id: "mint", plan: "paid" });
  assert.deepStrictEqual(
    tenants.all().map((one) => one.id),
    ["acme", "mint", "zeta"],
  );
  assert.deepStrictEqual(
    tenants.onPlan("paid").map((one) => one.id),
    ["mint", "zeta"],
  );
});

test("reads a tenant as one line", () => {
  assert.strictEqual(
    tenants.describe(tenants.add({ id: "acme", plan: "paid" })),
    "acme (paid)",
  );
});
