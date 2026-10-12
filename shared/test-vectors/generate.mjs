// Regenerates signing.json with Node's crypto module (an implementation independent of the
// Worker and the iOS client). Run: node shared/test-vectors/generate.mjs
import { createHash, createHmac } from "node:crypto";
import { writeFileSync } from "node:fs";

const secret = Buffer.from(Array.from({ length: 32 }, (_, i) => i));
const tokenId = "Tk7f3c9a2b1d04e5";
const b64url = (buf) => buf.toString("base64url");

const cases = [
  { name: "GET without body", method: "GET", pathAndQuery: "/v1/device", body: "" },
  {
    name: "GET with percent-encoded Arabic query",
    method: "GET",
    pathAndQuery: "/v1/foods/search?q=%D9%81%D9%88%D9%84&lang=ar",
    body: "",
  },
  {
    name: "POST JSON with Arabic text",
    method: "POST",
    pathAndQuery: "/v1/analyze/text",
    body: JSON.stringify({ text: "نص فرخة مشوية مع رز وسلطة", advanced: false }),
  },
  { name: "DELETE without body", method: "DELETE", pathAndQuery: "/v1/device", body: "" },
].map((c, i) => {
  const timestamp = String(1760184000000 + i * 1000);
  const nonce = b64url(Buffer.from(Array.from({ length: 16 }, (_, j) => (i * 16 + j) & 0xff)));
  const bodySha256 = createHash("sha256").update(c.body, "utf8").digest("hex");
  const canonical = ["LK1", c.method, c.pathAndQuery, timestamp, nonce, bodySha256].join("\n");
  const signature = b64url(createHmac("sha256", secret).update(canonical, "utf8").digest());
  return { ...c, timestamp, nonce, bodySha256, canonical, signature };
});

const vectors = {
  description: "Request-signing test vectors (ADR-013). Body is UTF-8 text; signature is base64url HMAC-SHA256.",
  token: `lk1_${tokenId}_${b64url(secret)}`,
  tokenId,
  secretBase64url: b64url(secret),
  cases,
};
writeFileSync(new URL("./signing.json", import.meta.url), JSON.stringify(vectors, null, 2) + "\n");
console.log(`wrote ${cases.length} cases`);
