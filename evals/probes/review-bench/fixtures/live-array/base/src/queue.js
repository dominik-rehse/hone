const store = require("./store.js");

// The ticket an agent takes next: the one that has waited longest.
function nextInQueue() {
  return store.all().find(store.isOpen) ?? null;
}

// Every open ticket.
function openTickets() {
  return store.all().filter(store.isOpen);
}

function queueDepth() {
  return openTickets().length;
}

// Hand the next ticket to an agent and give it back.
function assignNext(agent) {
  const ticket = nextInQueue();
  if (!ticket) return null;
  return store.assign(ticket.id, agent);
}

// The open tickets one agent holds.
function assignedTo(agent) {
  return openTickets().filter((ticket) => ticket.assignee === agent);
}

module.exports = { nextInQueue, openTickets, queueDepth, assignNext, assignedTo };
