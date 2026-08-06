export const recognitionContract = Object.freeze({
  schemaVersion: 1,
  maximumDecodedImageBytes: 2 * 1024 * 1024,
  maximumRequestBytes: 2_850_000,
  maximumProviderResponseBytes: 64 * 1024,
  allowedImageMimeTypes: Object.freeze(["image/jpeg"]),
  allowedBarcodeTypes: Object.freeze([
    "ean13",
    "ean8",
    "upcA",
    "upcE",
    "unknown",
  ]),
});

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const base64Pattern = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

export function validateRecognitionRequest(input) {
  if (!isPlainObject(input) || !hasOnlyKeys(
    input,
    ["schemaVersion", "requestId", "image", "barcode"],
    ["schemaVersion", "requestId", "image"],
  )) {
    return invalid("invalid_request");
  }
  if (input.schemaVersion !== recognitionContract.schemaVersion) {
    return invalid("unsupported_schema");
  }
  if (typeof input.requestId !== "string" || !uuidPattern.test(input.requestId)) {
    return invalid("invalid_request_id");
  }
  if (!isPlainObject(input.image) || !hasOnlyKeys(
    input.image,
    ["mimeType", "imageBase64"],
    ["mimeType", "imageBase64"],
  )) {
    return invalid("invalid_image");
  }
  if (!recognitionContract.allowedImageMimeTypes.includes(input.image.mimeType)) {
    return invalid("unsupported_image");
  }
  if (
    typeof input.image.imageBase64 !== "string" ||
    input.image.imageBase64.length < 16 ||
    input.image.imageBase64.length > 2_800_000 ||
    !base64Pattern.test(input.image.imageBase64)
  ) {
    return invalid("invalid_image");
  }

  const decodedLength = base64DecodedLength(input.image.imageBase64);
  if (decodedLength > recognitionContract.maximumDecodedImageBytes) {
    return invalid("payload_too_large");
  }
  if (!hasJPEGSignature(input.image.imageBase64)) {
    return invalid("unsupported_image");
  }

  let barcode = null;
  if (input.barcode !== undefined && input.barcode !== null) {
    if (!isPlainObject(input.barcode) || !hasOnlyKeys(
      input.barcode,
      ["value", "type"],
      ["value", "type"],
    )) {
      return invalid("invalid_barcode");
    }
    if (
      typeof input.barcode.value !== "string" ||
      !/^[0-9]{6,32}$/.test(input.barcode.value) ||
      !recognitionContract.allowedBarcodeTypes.includes(input.barcode.type)
    ) {
      return invalid("invalid_barcode");
    }
    barcode = Object.freeze({
      value: input.barcode.value,
      type: input.barcode.type,
    });
  }

  return {
    ok: true,
    value: Object.freeze({
      schemaVersion: recognitionContract.schemaVersion,
      requestId: input.requestId,
      image: Object.freeze({
        mimeType: input.image.mimeType,
        imageBase64: input.image.imageBase64,
      }),
      barcode,
    }),
  };
}

export function normalizeGeminiResponse(input, requestId) {
  if (!isPlainObject(input) || !Array.isArray(input.candidates)) {
    return invalid("invalid_result");
  }
  const texts = [];
  for (const candidate of input.candidates.slice(0, 2)) {
    const parts = candidate?.content?.parts;
    if (!Array.isArray(parts)) continue;
    for (const part of parts.slice(0, 4)) {
      if (typeof part?.text === "string") texts.push(part.text);
    }
  }
  const text = texts.join("\n");
  if (text.length === 0 || text.length > 32_768) {
    return invalid("invalid_result");
  }

  let suggestion;
  try {
    suggestion = JSON.parse(text);
  } catch {
    return invalid("invalid_result");
  }
  if (!isPlainObject(suggestion)) return invalid("invalid_result");

  const productName = boundedString(suggestion.productName, 200);
  if (!productName) {
    return {
      ok: true,
      value: {
        schemaVersion: recognitionContract.schemaVersion,
        requestId,
        status: "no_match",
        product: null,
        messageCode: guidanceCode(suggestion.description),
      },
    };
  }

  const numericConfidence = Number(suggestion.confidence);
  const confidence = Number.isFinite(numericConfidence)
    ? Math.min(Math.max(numericConfidence, 0), 1)
    : 0;
  const searchKeywords = Array.isArray(suggestion.searchKeywords)
    ? deduplicatedStrings(suggestion.searchKeywords, 48, 8)
    : [];

  return {
    ok: true,
    value: {
      schemaVersion: recognitionContract.schemaVersion,
      requestId,
      status: "recognized",
      product: {
        productName,
        brand: boundedString(suggestion.brand, 160),
        category: boundedString(suggestion.category, 160),
        productType: boundedString(suggestion.productType, 160),
        flavor: boundedString(suggestion.flavor, 160),
        packageSize: boundedString(suggestion.packageSize, 80),
        packageType: boundedString(suggestion.packageType, 80),
        visibleText: boundedString(suggestion.visibleText, 500),
        confidence,
        searchKeywords,
      },
      messageCode: "review_result",
    },
  };
}

export function jsonError(code) {
  return JSON.stringify({
    schemaVersion: recognitionContract.schemaVersion,
    error: { code },
  });
}

export function base64DecodedLength(value) {
  if (typeof value !== "string" || value.length === 0) return 0;
  const padding = value.endsWith("==") ? 2 : value.endsWith("=") ? 1 : 0;
  return Math.floor((value.length * 3) / 4) - padding;
}

function hasJPEGSignature(value) {
  try {
    const leading = Uint8Array.from(atob(value.slice(0, 8)), (item) =>
      item.charCodeAt(0)
    );
    const trailing = Uint8Array.from(atob(value.slice(-8)), (item) =>
      item.charCodeAt(0)
    );
    return leading.length >= 3 &&
      leading[0] === 0xff &&
      leading[1] === 0xd8 &&
      leading[2] === 0xff &&
      trailing.length >= 2 &&
      trailing[trailing.length - 2] === 0xff &&
      trailing[trailing.length - 1] === 0xd9;
  } catch {
    return false;
  }
}

function guidanceCode(value) {
  const text = typeof value === "string" ? value.toLowerCase() : "";
  if (/multiple|several|more than one|clutter/.test(text)) {
    return "retake_single_product";
  }
  if (/blur|unclear|out of focus|too far|small|cropped/.test(text)) {
    return "retake_clearer_photo";
  }
  return "no_match";
}

function boundedString(value, maximum) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > maximum || /[\u0000-\u001f\u007f]/.test(trimmed)) {
    return null;
  }
  return trimmed;
}

function deduplicatedStrings(values, maximumLength, maximumCount) {
  const seen = new Set();
  const output = [];
  for (const value of values) {
    const normalized = boundedString(value, maximumLength);
    if (!normalized) continue;
    const key = normalized.toLocaleLowerCase("en-US");
    if (seen.has(key)) continue;
    seen.add(key);
    output.push(normalized);
    if (output.length === maximumCount) break;
  }
  return output;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function hasOnlyKeys(value, allowed, required) {
  const keys = Object.keys(value);
  return keys.every((key) => allowed.includes(key)) &&
    required.every((key) => Object.hasOwn(value, key));
}

function invalid(code) {
  return { ok: false, error: code };
}
