import type { Context } from "hono";
import type { ContentfulStatusCode } from "hono/utils/http-status";

export type AppLang = "ar" | "en";

/** Error codes shared with the iOS client (ADR-027). The app maps codes to its own copy. */
export const ERROR_CODES = [
  "invalid_request",
  "unauthorized",
  "session_expired",
  "device_revoked",
  "account_disabled",
  "bad_signature",
  "stale_request",
  "replayed_request",
  "invalid_credentials",
  "invalid_invite",
  "email_taken",
  "too_many_attempts",
  "rate_limited",
  "quota_exceeded",
  "forbidden",
  "not_found",
  "payload_too_large",
  "internal",
] as const;
export type ErrorCode = (typeof ERROR_CODES)[number];

const MESSAGES: Record<ErrorCode, Record<AppLang, string>> = {
  invalid_request: { ar: "الطلب غير صالح.", en: "The request isn't valid." },
  unauthorized: { ar: "سجّل الدخول من جديد.", en: "Please sign in again." },
  session_expired: { ar: "انتهت الجلسة. جارٍ التجديد…", en: "Your session expired. Renewing…" },
  device_revoked: {
    ar: "تم تسجيل خروج هذا الجهاز. سجّل الدخول من جديد.",
    en: "This device was signed out. Sign in again.",
  },
  account_disabled: { ar: "هذا الحساب موقوف.", en: "This account is disabled." },
  bad_signature: { ar: "تعذّر التحقق من الطلب.", en: "The request couldn't be verified." },
  stale_request: {
    ar: "وقت الجهاز غير مضبوط. اضبط الوقت وحاول مرة أخرى.",
    en: "Your device clock is off. Fix the time and try again.",
  },
  replayed_request: { ar: "تم رفض طلب مكرر.", en: "A repeated request was rejected." },
  invalid_credentials: {
    ar: "البريد أو كلمة المرور غير صحيحة.",
    en: "The email or password isn't correct.",
  },
  invalid_invite: { ar: "رمز الدعوة غير صالح.", en: "The invite code isn't valid." },
  email_taken: { ar: "هذا البريد مسجّل بالفعل.", en: "This email already has an account." },
  too_many_attempts: {
    ar: "محاولات كثيرة. انتظر قليلًا ثم حاول.",
    en: "Too many attempts. Wait a little and try again.",
  },
  rate_limited: {
    ar: "طلبات كثيرة في وقت قصير. انتظر قليلًا ثم حاول.",
    en: "Too many requests. Wait a moment and try again.",
  },
  quota_exceeded: {
    ar: "الخادم وصل لحده اليومي. التطبيق يعمل بدونه، حاول غدًا.",
    en: "The server reached its daily limit. The app works without it; try again tomorrow.",
  },
  forbidden: { ar: "غير مسموح.", en: "Not allowed." },
  not_found: { ar: "غير موجود.", en: "Not found." },
  payload_too_large: { ar: "البيانات كبيرة جدًا.", en: "The data is too large." },
  internal: { ar: "حدث خطأ غير متوقع.", en: "Something went wrong." },
};

const RETRYABLE: ReadonlySet<ErrorCode> = new Set([
  "session_expired",
  "stale_request",
  "too_many_attempts",
  "rate_limited",
  "quota_exceeded",
  "internal",
]);

export class ApiError extends Error {
  constructor(
    readonly code: ErrorCode,
    readonly status: ContentfulStatusCode,
    readonly details?: Record<string, unknown>,
  ) {
    super(code);
  }
}

export function langOf(c: Context): AppLang {
  return c.req.header("X-App-Lang") === "en" ? "en" : "ar";
}

export function errorBody(code: ErrorCode, lang: AppLang, details?: Record<string, unknown>) {
  return {
    error: {
      code,
      retryable: RETRYABLE.has(code),
      message: MESSAGES[code][lang],
      ...(details ? { details } : {}),
    },
  };
}

export function errorResponse(c: Context, err: ApiError) {
  return c.json(errorBody(err.code, langOf(c), err.details), err.status);
}
