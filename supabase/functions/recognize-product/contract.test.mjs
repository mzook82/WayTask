import assert from "node:assert/strict";
import test from "node:test";
import {
  base64DecodedLength,
  normalizeGeminiResponse,
  recognitionContract,
  validateRecognitionRequest,
} from "./contract.mjs";

const requestId = "123e4567-e89b-42d3-a456-426614174000";
const syntheticJPEG = Buffer.from([
  0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46,
  0x49, 0x46, 0x00, 0x01, 0xff, 0xd9,
]).toString("base64");

function validRequest() {
  return {
    schemaVersion: 1,
    requestId,
    image: { mimeType: "image/jpeg", imageBase64: syntheticJPEG },
    barcode: { value: "7290000000000", type: "ean13" },
  };
}

test("accepts only the explicit bounded request schema", () => {
  const result = validateRecognitionRequest(validRequest());
  assert.equal(result.ok, true);
  assert.equal(result.value.barcode.value, "7290000000000");
  assert.equal(base64DecodedLength(syntheticJPEG), 14);

  for (const forbidden of ["model", "prompt", "endpoint", "userId", "location"]) {
    const request = validRequest();
    request[forbidden] = "not allowed";
    assert.equal(validateRecognitionRequest(request).ok, false);
  }
});

test("rejects malformed, oversized, and unsupported image payloads", () => {
  const malformed = validRequest();
  malformed.image.imageBase64 = "not base64";
  assert.equal(validateRecognitionRequest(malformed).error, "invalid_image");

  const unsupported = validRequest();
  unsupported.image.mimeType = "image/png";
  assert.equal(
    validateRecognitionRequest(unsupported).error,
    "unsupported_image",
  );

  const oversized = validRequest();
  oversized.image.imageBase64 = Buffer.alloc(
    recognitionContract.maximumDecodedImageBytes + 1,
    0xff,
  ).toString("base64");
  assert.equal(
    validateRecognitionRequest(oversized).error,
    "payload_too_large",
  );
});

test("rejects QR text, malformed barcode data, and unknown schema fields", () => {
  const qr = validRequest();
  qr.barcode = { value: "https://private.invalid/path", type: "qr" };
  assert.equal(validateRecognitionRequest(qr).error, "invalid_barcode");

  const shortBarcode = validRequest();
  shortBarcode.barcode.value = "123";
  assert.equal(
    validateRecognitionRequest(shortBarcode).error,
    "invalid_barcode",
  );

  const imageWithExtraField = validRequest();
  imageWithExtraField.image.filename = "private-name.jpg";
  assert.equal(
    validateRecognitionRequest(imageWithExtraField).error,
    "invalid_image",
  );
});

test("normalizes and bounds provider output", () => {
  const provider = {
    candidates: [{
      content: {
        parts: [{
          text: JSON.stringify({
            productName: " Synthetic Product ",
            brand: "Synthetic Brand",
            category: "Synthetic Category",
            confidence: 1.8,
            visibleText: "Front label",
            searchKeywords: ["Test", "test", "Retail"],
          }),
        }],
      },
    }],
  };
  const result = normalizeGeminiResponse(provider, requestId);
  assert.equal(result.ok, true);
  assert.equal(result.value.status, "recognized");
  assert.equal(result.value.product.productName, "Synthetic Product");
  assert.equal(result.value.product.confidence, 1);
  assert.deepEqual(result.value.product.searchKeywords, ["Test", "Retail"]);
  assert.equal(result.value.requestId, requestId);
});

test("empty and malformed provider results never invent a product", () => {
  const noMatch = normalizeGeminiResponse({
    candidates: [{
      content: {
        parts: [{ text: JSON.stringify({ productName: "", confidence: 0 }) }],
      },
    }],
  }, requestId);
  assert.equal(noMatch.ok, true);
  assert.equal(noMatch.value.status, "no_match");
  assert.equal(noMatch.value.product, null);

  assert.equal(
    normalizeGeminiResponse({ candidates: [] }, requestId).ok,
    false,
  );
  assert.equal(
    normalizeGeminiResponse({
      candidates: [{ content: { parts: [{ text: "not-json" }] } }],
    }, requestId).ok,
    false,
  );
});
