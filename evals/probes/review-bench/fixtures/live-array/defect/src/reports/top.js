const store = require("../store.js");
const sla = require("../sla.js");

// The most urgent first, and within one priority the one that waited longest.
function byPriority(a, b) {
  const byRank = sla.rank(b.priority) - sla.rank(a.priority);
  return byRank !== 0 ? byRank : a.createdAt - b.createdAt;
}

// The n open tickets that have waited longest.
function topByAge(n = 5) {
  return store.all().filter(store.isOpen).slice(0, n);
}

// The n open tickets the dashboard puts at the top, the most urgent first.
function topByPriority(n = 5) {
  const tickets = store.all();
  tickets.sort(byPriority);
  return tickets.filter(store.isOpen).slice(0, n);
}

module.exports = { topByAge, topByPriority };
