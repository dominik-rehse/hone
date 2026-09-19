const { toIsoDate } = require("./dates.js");
const { lineTotalCents, sumCents, vatCents } = require("./money.js");
const paymentTerms = require("./terms.js");

const VAT_RATE = 0.19;

function createInvoice({ id, customer, issuedOn, terms, lines = [] }) {
  const chosen = terms == null ? paymentTerms.DEFAULT_TERMS : terms;
  if (!paymentTerms.TERMS.includes(chosen)) {
    throw new Error(`unknown payment terms: ${chosen}`);
  }
  return { id, customer, issuedOn, terms: chosen, lines, paidOn: null };
}

// The day the invoice falls due, written out.
function dueOn(invoice) {
  return toIsoDate(paymentTerms.dueDate(invoice.issuedOn, invoice.terms));
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
  NET_DAYS: paymentTerms.NET_DAYS,
  VAT_RATE,
  createInvoice,
  dueOn,
  netCents,
  totalCents,
  markPaid,
  isPaid,
};
