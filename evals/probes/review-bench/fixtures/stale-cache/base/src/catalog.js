const store = require("./store.js");
const quotes = require("./quotes.js");

// The price book the service starts from, read once at boot.
function loadInitial(book) {
  store.reset();
  quotes.clear();
  return store.setMany(Object.entries(book));
}

module.exports = { loadInitial };
