import { describe, expect, it } from "vitest";
import vectors from "../../shared/test-vectors/signing.json";
import { canonicalString, formatToken, parseToken, sign } from "../src/auth/signing";
import { base64urlDecode } from "../src/lib/crypto";

describe("request signing matches shared/test-vectors/signing.json", () => {
  const secret = base64urlDecode(vectors.secretBase64url);

  it("parses and re-formats the token", () => {
    const parsed = parseToken(vectors.token);
    expect(parsed?.tokenId).toBe(vectors.tokenId);
    expect(parsed && formatToken(parsed.tokenId, parsed.secret)).toBe(vectors.token);
  });

  it.each(vectors.cases)("$name", async (c) => {
    if (!secret) throw new Error("bad vector secret");
    expect(await canonicalString(c)).toBe(c.canonical);
    expect(await sign(secret, c)).toBe(c.signature);
  });

  it("rejects malformed tokens", () => {
    expect(parseToken("lk1_short_abc")).toBeNull();
    expect(parseToken(vectors.token.replace("lk1_", "lk2_"))).toBeNull();
    expect(parseToken(`${vectors.token}x`)).toBeNull();
  });
});
