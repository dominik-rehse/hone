const sla = require("./sla.js");

// Minutes as hours and minutes: 125 reads "2h 5m", 20 reads "20m".
function formatMinutes(minutes) {
  const total = Math.abs(Math.round(minutes));
  const hours = Math.floor(total / 60);
  const rest = total % 60;
  return hours === 0 ? `${rest}m` : `${hours}h ${rest}m`;
}

// One ticket on one line, for a mail or a log.
function formatTicket(ticket) {
  const who = ticket.assignee ?? "unassigned";
  return `#${ticket.id} [${ticket.priority}] ${ticket.subject} (${ticket.status}, ${who})`;
}

// One ticket as the queue view shows it, with the time on its target.
function formatQueueLine(ticket, now) {
  const left = sla.minutesLeft(ticket, now);
  const state = sla.isBreached(ticket, now) ? "over" : "left";
  return `#${ticket.id} ${ticket.priority.padEnd(6)} ${formatMinutes(left)} ${state}  ${ticket.subject}`;
}

// A dashboard report: its title, then one numbered line per ticket.
function formatReport(title, tickets, now) {
  const rows = tickets.map((ticket, i) => `${i + 1}. ${formatQueueLine(ticket, now)}`);
  return [title, ...rows].join("\n");
}

module.exports = { formatMinutes, formatTicket, formatQueueLine, formatReport };
