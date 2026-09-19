const { fromIsoDate, daysBetweenUtc, isAfterUtc } = require("./dates.js");
const { dueOn, isPaid } = require("./invoice.js");

// Has the invoice passed its due day by `on`?
function isOverdue(invoice, on) {
  if (isPaid(invoice)) {
    return false;
  }
  return isAfterUtc(fromIsoDate(on), fromIsoDate(dueOn(invoice)));
}

// How many days past its due day the invoice is, and zero while it is not.
function daysOverdue(invoice, on) {
  if (!isOverdue(invoice, on)) {
    return 0;
  }
  return daysBetweenUtc(fromIsoDate(dueOn(invoice)), fromIsoDate(on));
}

// The buckets collections works through, widest last.
const BUCKETS = [
  { name: "current", upTo: 0 },
  { name: "1-30", upTo: 30 },
  { name: "31-60", upTo: 60 },
  { name: "61-90", upTo: 90 },
  { name: "90+", upTo: Infinity },
];

// Which bucket the invoice sits in on a day.
function agingBucket(invoice, on) {
  const days = daysOverdue(invoice, on);
  return BUCKETS.find((bucket) => days <= bucket.upTo).name;
}

// The invoices that are overdue on a day, the longest overdue first.
function overdueList(invoices, on) {
  return invoices
    .filter((invoice) => isOverdue(invoice, on))
    .sort((one, other) => daysOverdue(other, on) - daysOverdue(one, on));
}

module.exports = { isOverdue, daysOverdue, BUCKETS, agingBucket, overdueList };
