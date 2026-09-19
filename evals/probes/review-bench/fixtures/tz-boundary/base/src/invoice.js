const { addDaysUtc, fromIsoDate, toIsoDate } = require("./dates.js");
const { lineTotalCents, sumCents, vatCents } = require("./money.js");

// How long each payment term gives the customer.
const NET_DAYS = { "on-receipt": 0, "net-7": 7, "net-14": 14, "net-30": 30 };

const VAT_RATE = 0.19;

function createInvoice({ id, customer, issuedOn, terms = "net-30", lines = [] }) {
  return { id, customer, issuedOn, terms, lines, paidOn: null };
}

// The day the invoice falls due, written out.
function dueOn(invoice) {
  const days = NET_DAYS[invoice.terms];
  if (days === undefined) {
    throw new Error(`unknown payment terms: ${invoice.terms}`);
  }
  return toIsoDate(addDaysUtc(fromIsoDate(invoice.issuedOn), days));
}

// What the customer owes before tax.
function netCents(invoice) {
  return sumCents(invoice.lines.map(lineTotalCents));
}

// What the customer owes with tax.
function totalCents(invoice) {
  const net = netCents(invoice);
  return net + vatCents(net, VAT_RATE);
}

// The same invoice, marked paid on a day.
function markPaid(invoice, paidOn) {
  return { ...invoice, paidOn };
}

function isPaid(invoice) {
  return invoice.paidOn !== null;
}

module.exports = {
  NET_DAYS,
  VAT_RATE,
  createInvoice,
  dueOn,
  netCents,
  totalCents,
  markPaid,
  isPaid,
};
