import { describe, expect, it } from "vitest";
import vectors from "../../shared/test-vectors/signing.json";
import { canonicalString, sign } from "../src/auth/signing";
import { base64urlDecode } from "../src/lib/crypto";

describe("LK2 signing matches the shared vectors", () => {
  const secret = base64urlDecode(vectors.secret);
  it("has a 32-byte secret", () => expect(secret?.length).toBe(32));

  for (const v of vectors.vectors) {
    it(v.name, async () => {
      if (!secret) throw new Error("bad secret");
      const input = {
        method: v.method,
        pathAndQuery: v.pathAndQuery,
        timestamp: v.timestamp,
        nonce: v.nonce,
        deviceId: v.deviceId,
        body: v.body,
      };
      expect(await canonicalString(input)).toBe(v.canonical);
      expect(await sign(secret, input)).toBe(v.signature);
    });
  }
});
