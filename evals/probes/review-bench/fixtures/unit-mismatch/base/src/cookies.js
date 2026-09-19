const config = require("./config.js");

// The Set-Cookie header the browser gets when a session begins.
function sessionCookie(session, settings = config.current()) {
  const parts = [
    `${settings.cookieName}=${session.id}`,
    "Path=/",
    "HttpOnly",
    "SameSite=Lax",
    `Max-Age=${settings.sessionTtl}`,
  ];
  if (settings.secureCookie) {
    parts.push("Secure");
  }
  return parts.join("; ");
}

// The header that takes the cookie away again.
function clearCookie(settings = config.current()) {
  return `${settings.cookieName}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`;
}

// One cookie out of a Cookie header, or null when it is not in there.
function readCookie(header, name) {
  if (typeof header !== "string") {
    return null;
  }
  for (const pair of header.split(";")) {
    const at = pair.indexOf("=");
    if (at === -1) {
      continue;
    }
    if (pair.slice(0, at).trim() === name) {
      return pair.slice(at + 1).trim();
    }
  }
  return null;
}

module.exports = { sessionCookie, clearCookie, readCookie };
