// The tickets the support desk holds, and the small operations on one of them.

const tickets = [];
let nextId = 1;
let clock = () => Date.now();

const STATUS = { open: "open", closed: "closed" };

// Take a new ticket and give it its id.
function add({ subject, requester, priority = "normal" }) {
  const ticket = {
    id: nextId,
    subject,
    requester,
    priority,
    createdAt: clock(),
    status: STATUS.open,
    assignee: null,
    closedAt: null,
  };
  nextId += 1;
  tickets.push(ticket);
  return ticket;
}

function all() {
  return tickets;
}

function get(id) {
  return tickets.find((ticket) => ticket.id === id) ?? null;
}

function isOpen(ticket) {
  return ticket.status === STATUS.open;
}

function assign(id, agent) {
  const ticket = get(id);
  if (!ticket) return null;
  ticket.assignee = agent;
  return ticket;
}

function close(id) {
  const ticket = get(id);
  if (!ticket) return null;
  ticket.status = STATUS.closed;
  ticket.closedAt = clock();
  return ticket;
}

function setPriority(id, priority) {
  const ticket = get(id);
  if (!ticket) return null;
  ticket.priority = priority;
  return ticket;
}

// Throw everything away and start over, on the clock given.
function reset(now = () => Date.now()) {
  tickets.length = 0;
  nextId = 1;
  clock = now;
}

module.exports = {
  add,
  all,
  get,
  isOpen,
  assign,
  close,
  setPriority,
  reset,
  STATUS,
};
