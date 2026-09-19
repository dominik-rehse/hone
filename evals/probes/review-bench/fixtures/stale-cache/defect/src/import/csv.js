// The supplier sends a two column file: a header line, then one price a line.
const HEADER = ["sku", "price"];

class CsvError extends Error {
  constructor(message, code, lineNo) {
    super(message);
    this.name = "CsvError";
    this.code = code;
    this.lineNo = lineNo;
  }
}

function splitFields(line) {
  return line.split(",").map((field) => field.trim());
}

// The rows of a supplier file, each with the line it sat on. Blank lines are
// not rows. Throws a CsvError with the code BAD_HEADER when the first line
// that carries anything is not the header this format has, with the line that
// line sat on.
function parseCsv(text) {
  const numbered = String(text)
    .replace(/^\ufeff/, "")
    .split(/\r?\n/)
    .map((line, i) => ({ lineNo: i + 1, text: line }))
    .filter((line) => line.text.trim() !== "");
  const head = numbered[0];
  if (head === undefined || splitFields(head.text).join(",") !== HEADER.join(",")) {
    throw new CsvError(
      `the first line must read ${HEADER.join(",")}`,
      "BAD_HEADER",
      head === undefined ? 1 : head.lineNo,
    );
  }
  return numbered.slice(1).map((line) => ({ lineNo: line.lineNo, fields: splitFields(line.text) }));
}

module.exports = { parseCsv, CsvError, HEADER };
