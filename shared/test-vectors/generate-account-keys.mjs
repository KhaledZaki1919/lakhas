// Generates shared/test-vectors/account-keys.json: the phone-side key derivation of ADR-027 §1–2,
// computed with Node's crypto. The Swift client must reproduce every value.
// Run: node shared/test-vectors/generate-account-keys.mjs
//
//   password   = UTF-8 of the NFC-normalized password
//   stretched  = PBKDF2-SHA256(password, kdfSalt, iterations, 32)
//   authKey    = HKDF-SHA256(stretched, salt: authSalt, info: "lakhas/auth/v1", 32)      → sent
//   passwordKEK= HKDF-SHA256(stretched, salt: encSalt,  info: "lakhas/backup-kek/v1", 32) → never sent
//   recovery code: 16 random bytes, shown as RFC 4648 base32 (no padding, 26 chars) in groups of 4
//   recoveryAuth = HKDF-SHA256(codeBytes, salt: recoverySalt, info: "lakhas/recovery-auth/v1", 32)
//   recoveryKEK  = HKDF-SHA256(codeBytes, salt: recoverySalt, info: "lakhas/recovery-kek/v1", 32)
//   envelope   = AES-256-GCM(key: KEK, nonce: 12 bytes, plaintext: DEK (32 bytes),
//                aad: "lakhas/dek/v1/<kind>") → wrapped = ciphertext ‖ tag (48 bytes)
import { createCipheriv, hkdfSync, pbkdf2Sync } from "node:crypto";
import { writeFileSync } from "node:fs";

const b64url = (buf) => Buffer.from(buf).toString("base64url");
const bytes = (n, seed) => Buffer.from(Array.from({ length: n }, (_, i) => (i * 31 + seed) & 0xff));
const hkdf = (ikm, salt, info) => Buffer.from(hkdfSync("sha256", ikm, salt, Buffer.from(info, "utf8"), 32));

const BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
function base32(buf) {
  let bits = 0, value = 0, out = "";
  for (const byte of buf) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += BASE32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += BASE32[(value << (5 - bits)) & 31];
  return out;
}
const grouped = (code) => code.match(/.{1,4}/g).join("-");

function wrap(kek, nonce, dek, kind) {
  const cipher = createCipheriv("aes-256-gcm", kek, nonce);
  cipher.setAAD(Buffer.from(`lakhas/dek/v1/${kind}`, "utf8"));
  return Buffer.concat([cipher.update(dek), cipher.final(), cipher.getAuthTag()]);
}

// Few iterations keep the test fast; the derivation is identical at 600,000.
const cases = [
  { name: "ascii", password: "correct horse battery", iterations: 1000 },
  { name: "arabic-nfc", password: "كلمة سرّ طويلة ١٢٣", iterations: 1000 },
  { name: "decomposed-input-is-normalized", password: "café au lait", iterations: 1000 },
  { name: "production-iterations", password: "Lakhas passphrase 2026", iterations: 600000 },
];

const vectors = cases.map((c, i) => {
  const kdfSalt = bytes(16, 10 + i), authSalt = bytes(16, 50 + i), encSalt = bytes(16, 90 + i);
  const recoverySalt = bytes(16, 130 + i), codeBytes = bytes(16, 170 + i);
  const dek = bytes(32, 210 + i), passwordNonce = bytes(12, 3 + i), recoveryNonce = bytes(12, 7 + i);
  const stretched = pbkdf2Sync(Buffer.from(c.password.normalize("NFC"), "utf8"), kdfSalt, c.iterations, 32, "sha256");
  const authKey = hkdf(stretched, authSalt, "lakhas/auth/v1");
  const passwordKEK = hkdf(stretched, encSalt, "lakhas/backup-kek/v1");
  const recoveryAuth = hkdf(codeBytes, recoverySalt, "lakhas/recovery-auth/v1");
  const recoveryKEK = hkdf(codeBytes, recoverySalt, "lakhas/recovery-kek/v1");
  return {
    name: c.name,
    password: c.password,
    iterations: c.iterations,
    kdfSalt: b64url(kdfSalt),
    authSalt: b64url(authSalt),
    encSalt: b64url(encSalt),
    stretched: b64url(stretched),
    authKey: b64url(authKey),
    passwordKEK: b64url(passwordKEK),
    recoverySalt: b64url(recoverySalt),
    recoveryCodeBytes: b64url(codeBytes),
    recoveryCode: grouped(base32(codeBytes)),
    recoveryAuth: b64url(recoveryAuth),
    recoveryKEK: b64url(recoveryKEK),
    dek: b64url(dek),
    passwordEnvelope: { nonce: b64url(passwordNonce), wrapped: b64url(wrap(passwordKEK, passwordNonce, dek, "password")) },
    recoveryEnvelope: { nonce: b64url(recoveryNonce), wrapped: b64url(wrap(recoveryKEK, recoveryNonce, dek, "recovery")) },
  };
});

writeFileSync(
  new URL("./account-keys.json", import.meta.url),
  JSON.stringify({ kdf: "pbkdf2-sha256", vectors }, null, 2) + "\n",
);
console.log(`account-keys.json: ${vectors.length} vectors`);
