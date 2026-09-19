const { formatCents, lineTotalCents, vatCents } = require("./money.js");
const { netCents, totalCents, dueOn, VAT_RATE } = require("./invoice.js");
const { daysOverdue } = require("./overdue.js");
const { labelFor } = require("./terms.js");

// The column the item name has, now that the head carries two lines more.
const NAME_WIDTH = 24;

// The item's name, cut to its column when it runs past it.
function fitName(name) {
  const text = String(name);
  return text.length <= NAME_WIDTH ? text : `${text.slice(0, NAME_WIDTH - 3)}...`;
}

// One line of the invoice body.
function renderLine(line) {
  const quantity = String(line.quantity).padStart(3);
  return `  ${quantity} x ${fitName(line.name)}  ${formatCents(lineTotalCents(line))}`;
}

// The invoice as the customer gets it.
function renderInvoice(invoice) {
  const net = netCents(invoice);
  return [
    `Invoice ${invoice.id}`,
    `To      ${invoice.customer}`,
    `Issued  ${invoice.issuedOn}`,
    `Terms   ${labelFor(invoice.terms)}`,
    `Due     ${dueOn(invoice)}`,
    "",
    ...invoice.lines.map(renderLine),
    "",
    `Net     ${formatCents(net)}`,
    `VAT     ${formatCents(vatCents(net, VAT_RATE))}`,
    `Total   ${formatCents(totalCents(invoice))}`,
  ].join("\n");
}

// The line the collections mail carries for one invoice.
function renderReminderLine(invoice, on) {
  const days = daysOverdue(invoice, on);
  const age = days === 0 ? "not yet due" : `${days} days over`;
  return `${invoice.id}  ${invoice.customer}  ${formatCents(totalCents(invoice))}  ${age}`;
}

module.exports = { NAME_WIDTH, fitName, renderLine, renderInvoice, renderReminderLine };
