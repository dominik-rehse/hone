const { formatCents, lineTotalCents, vatCents } = require("./money.js");
const { netCents, totalCents, VAT_RATE } = require("./invoice.js");
const { daysOverdue } = require("./overdue.js");

// One line of the invoice body.
function renderLine(line) {
  const quantity = String(line.quantity).padStart(3);
  return `  ${quantity} x ${line.name}  ${formatCents(lineTotalCents(line))}`;
}

// The invoice as the customer gets it.
function renderInvoice(invoice) {
  const net = netCents(invoice);
  return [
    `Invoice ${invoice.id}`,
    `To      ${invoice.customer}`,
    `Issued  ${invoice.issuedOn}`,
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

module.exports = { renderLine, renderInvoice, renderReminderLine };
