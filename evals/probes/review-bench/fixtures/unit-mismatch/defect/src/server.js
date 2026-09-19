const clock = require("./clock.js");
const config = require("./config.js");
const cookies = require("./cookies.js");
const expiry = require("./expiry.js");
const sessions = require("./sessions.js");

// How long somebody is kept out after too many wrong passwords.
const LOCKOUT_MS = 15 * 60 * 1000;

// The password of the one account this toy service has.
const PASSWORD = "open-sesame";

const attempts = new Map();

function attemptsOf(userId) {
  return attempts.get(userId) ?? { count: 0, lockedUntil: 0 };
}

// Sign in. Too many wrong passwords in a row lock the account for a while.
function login(userId, password) {
  const record = attemptsOf(userId);
  if (record.lockedUntil > clock.now()) {
    return { status: 429, headers: {}, body: null };
  }
  if (password !== PASSWORD) {
    record.count += 1;
    if (record.count >= config.current().loginAttempts) {
      record.lockedUntil = clock.after(LOCKOUT_MS);
      record.count = 0;
    }
    attempts.set(userId, record);
    return { status: 401, headers: {}, body: null };
  }
  attempts.delete(userId);
  const session = expiry.touch(sessions.create(userId));
  return {
    status: 200,
    headers: { "Set-Cookie": cookies.sessionCookie(session) },
    body: { userId },
  };
}

// The session one request carries, or null when it carries none we know.
function sessionOf(cookieHeader) {
  const id = cookies.readCookie(cookieHeader, config.current().cookieName);
  return id === null ? null : sessions.get(id);
}

// Who is asking? A request that arrives in time carries its session forward.
function whoami(cookieHeader) {
  const session = sessionOf(cookieHeader);
  if (session === null) {
    return { status: 401, headers: {}, body: null };
  }
  if (expiry.isExpired(session, clock.now())) {
    sessions.destroy(session.id);
    return { status: 401, headers: { "Set-Cookie": cookies.clearCookie() }, body: null };
  }
  expiry.touch(session);
  return {
    status: 200,
    headers: { "Set-Cookie": cookies.sessionCookie(session) },
    body: { userId: session.userId },
  };
}

// The pass the housekeeping timer makes. Gives back how many sessions it took.
function runSweep() {
  return expiry.sweep(clock.now());
}

// Sign out, and take the cookie away with it.
function logout(cookieHeader) {
  const session = sessionOf(cookieHeader);
  if (session !== null) {
    sessions.destroy(session.id);
  }
  return { status: 200, headers: { "Set-Cookie": cookies.clearCookie() }, body: null };
}

function resetAttempts() {
  attempts.clear();
}

module.exports = {
  login,
  whoami,
  logout,
  sessionOf,
  runSweep,
  resetAttempts,
  LOCKOUT_MS,
  PASSWORD,
};
