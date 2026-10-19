// Generates shared/test-vectors/signing.json: LK2 request-signing vectors (ADR-027 §1),
// computed with Node's crypto independently of the Worker and Swift implementations.
// Run: node shared/test-vectors/generate-signing.mjs
import { createHash, createHmac } from "node:crypto";
import { writeFileSync } from "node:fs";

const b64url = (buf) => Buffer.from(buf).toString("base64url");
const secret = Buffer.from(Array.from({ length: 32 }, (_, i) => i * 7 + 1));

const cases = [
  { name: "get-no-body", method: "GET", pathAndQuery: "/v1/account", body: "" },
  {
    name: "post-json",
    method: "POST",
    pathAndQuery: "/v1/auth/refresh",
    body: '{"refreshToken":"rt_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}',
  },
  { name: "query-and-arabic", method: "PATCH", pathAndQuery: "/v1/account?lang=ar", body: '{"note":"كشري"}' },
  { name: "lowercase-method", method: "delete", pathAndQuery: "/v1/account/devices/AAAAAAAAAAAAAAAAAAAAAA", body: "" },
];

const vectors = cases.map((c, i) => {
  const timestamp = String(1760000000000 + i * 1000);
  const nonce = b64url(Buffer.alloc(16, i + 1));
  const deviceId = b64url(Buffer.alloc(16, 0xa0 + i));
  const bodyHash = createHash("sha256").update(c.body, "utf8").digest("hex");
  const canonical = ["LK2", c.method.toUpperCase(), c.pathAndQuery, timestamp, nonce, deviceId, bodyHash].join("\n");
  const signature = b64url(createHmac("sha256", secret).update(canonical, "utf8").digest());
  return { ...c, timestamp, nonce, deviceId, canonical, signature };
});

writeFileSync(
  new URL("./signing.json", import.meta.url),
  JSON.stringify({ version: "LK2", secret: b64url(secret), vectors }, null, 2) + "\n",
);
console.log(`signing.json: ${vectors.length} vectors`);
