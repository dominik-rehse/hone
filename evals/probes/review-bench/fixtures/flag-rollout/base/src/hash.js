// The one string hash this service uses. The same text gives the same number
// in every process and after a restart, which is what a stable key needs.
function hash32(text) {
  let h = 0;
  for (let i = 0; i < text.length; i += 1) {
    h = ((h << 5) - h + text.charCodeAt(i)) | 0;
  }
  return h;
}

// The text a pair of strings hashes under.
function keyOf(left, right) {
  return `${left}:${right}`;
}

module.exports = { hash32, keyOf };
