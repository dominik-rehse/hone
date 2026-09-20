const hash = require("./hash.js");

// A weak etag for a body the admin screen polls every few seconds.
function etagFor(body) {
  const text = typeof body === "string" ? body : JSON.stringify(body);
  return `W/"${hash.hash32(text).toString(36)}"`;
}

// Whether the client's If-None-Match header covers this etag.
function matches(etag, header) {
  if (typeof header !== "string" || header === "") {
    return false;
  }
  return header
    .split(",")
    .map((part) => part.trim())
    .includes(etag);
}

module.exports = { etagFor, matches };
