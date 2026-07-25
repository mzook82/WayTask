"use strict";

const QUOTES = new Set([
  "'",
  "\"",
  "`",
  "´",
  "‘",
  "’",
  "‚",
  "‛",
  "“",
  "”",
  "„",
  "‟",
  "׳",
  "״",
]);

const FINAL_LETTERS = new Map([
  ["ך", "כ"],
  ["ם", "מ"],
  ["ן", "נ"],
  ["ף", "פ"],
  ["ץ", "צ"],
]);

const LETTER_OR_NUMBER = /[\p{L}\p{N}]/u;
const MARK = /\p{M}/u;

function normalize(input) {
  const source = String(input ?? "")
    .normalize("NFKD")
    .toLocaleLowerCase("he-IL");
  let value = "";
  let separatorPending = false;

  for (const scalar of source) {
    if (QUOTES.has(scalar) || MARK.test(scalar)) {
      continue;
    }

    if (LETTER_OR_NUMBER.test(scalar)) {
      if (separatorPending && value.length > 0) {
        value += " ";
      }
      value += FINAL_LETTERS.get(scalar) ?? scalar;
      separatorPending = false;
    } else if (value.length > 0) {
      separatorPending = true;
    }
  }

  return {
    value,
    tokens: value.length === 0 ? [] : value.split(" "),
  };
}

function normalizedValue(input) {
  return normalize(input).value;
}

module.exports = {
  normalize,
  normalizedValue,
};
