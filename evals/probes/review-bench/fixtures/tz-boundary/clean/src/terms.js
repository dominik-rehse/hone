const { addDaysUtc, fromIsoDate } = require("./dates.js");

// How long each payment term gives the customer.
const NET_DAYS = { "on-receipt": 0, "net-7": 7, "net-14": 14, "net-30": 30 };

const END_OF_MONTH = "end-of-month";
const DEFAULT_TERMS = "net-30";

// Every term the billing form offers, in the order it lists them.
const TERMS = [...Object.keys(NET_DAYS), END_OF_MONTH];

// How the billing form names each term.
const LABELS = {
  "on-receipt": "on receipt",
  "net-7": "within 7 days",
  "net-14": "within 14 days",
  "net-30": "within 30 days",
  [END_OF_MONTH]: "end of month",
};

// The last day of the month the invoice went out in.
function lastDayOfMonth(issuedOn) {
  const issued = fromIsoDate(issuedOn);
  const year = issued.getUTCFullYear();
  const month = issued.getUTCMonth();
  return new Date(Date.UTC(year, month + 1, 0));
}

// The day an invoice issued on `issuedOn` falls due under `terms`.
function dueDate(issuedOn, terms) {
  const chosen = terms == null ? DEFAULT_TERMS : terms;
  if (chosen === END_OF_MONTH) {
    return lastDayOfMonth(issuedOn);
  }
  const days = NET_DAYS[chosen];
  if (days === undefined) {
    throw new Error(`unknown payment terms: ${chosen}`);
  }
  return addDaysUtc(fromIsoDate(issuedOn), days);
}

function labelFor(terms) {
  const chosen = terms == null ? DEFAULT_TERMS : terms;
  return LABELS[chosen] ?? chosen;
}

module.exports = {
  NET_DAYS,
  TERMS,
  LABELS,
  END_OF_MONTH,
  DEFAULT_TERMS,
  dueDate,
  labelFor,
};
