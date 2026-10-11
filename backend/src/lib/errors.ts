import type { Context } from "hono";
import type { ContentfulStatusCode } from "hono/utils/http-status";

export type AppLang = "ar" | "en";

/** Error codes shared with the iOS client (see shared/openapi.yaml → ErrorCode). */
export const ERROR_CODES = [
  "invalid_request",
  "unauthorized",
  "token_revoked",
  "bad_signature",
  "stale_request",
  "replayed_request",
  "cap_reached",
  "daily_cap",
  "rate_limited",
  "ai_unavailable",
  "ai_invalid_output",
  "not_found",
  "not_implemented",
  "unsupported_url",
  "fetch_failed",
  "payload_too_large",
  "internal",
] as const;
export type ErrorCode = (typeof ERROR_CODES)[number];

const MESSAGES: Record<ErrorCode, Record<AppLang, string>> = {
  invalid_request: { ar: "الطلب غير صالح.", en: "The request isn't valid." },
  unauthorized: { ar: "رمز الجهاز غير صالح.", en: "This device token isn't valid." },
  token_revoked: { ar: "تم إلغاء رمز هذا الجهاز.", en: "This device token was revoked." },
  bad_signature: { ar: "تعذّر التحقق من الطلب.", en: "The request couldn't be verified." },
  stale_request: {
    ar: "وقت الجهاز غير مضبوط. اضبط الوقت وحاول مرة أخرى.",
    en: "Your device clock is off. Fix the time and try again.",
  },
  replayed_request: { ar: "تم رفض طلب مكرر.", en: "A repeated request was rejected." },
  cap_reached: {
    ar: "وصلت للحد اليومي لهذه الميزة. يتجدد غدًا.",
    en: "You've reached today's limit for this feature. It resets tomorrow.",
  },
  daily_cap: {
    ar: "وصلت للحد اليومي للتحليل بالذكاء الاصطناعي.",
    en: "You've reached today's AI limit.",
  },
  rate_limited: {
    ar: "طلبات كثيرة في وقت قصير. انتظر قليلًا ثم حاول.",
    en: "Too many requests. Wait a moment and try again.",
  },
  ai_unavailable: {
    ar: "خدمة التحليل غير متاحة الآن. حاول بعد قليل.",
    en: "Analysis isn't available right now. Try again shortly.",
  },
  ai_invalid_output: {
    ar: "لم نتمكن من فهم نتيجة التحليل. حاول مرة أخرى.",
    en: "We couldn't read the analysis result. Try again.",
  },
  not_found: { ar: "غير موجود.", en: "Not found." },
  not_implemented: { ar: "هذه الميزة غير متاحة بعد.", en: "This feature isn't available yet." },
  unsupported_url: {
    ar: "هذا الرابط غير مدعوم. استخدم تيك توك أو إنستجرام أو يوتيوب.",
    en: "This link isn't supported. Use TikTok, Instagram or YouTube.",
  },
  fetch_failed: {
    ar: "تعذّر قراءة الرابط. جرّب استيراد لقطة شاشة بدلًا منه.",
    en: "We couldn't read that link. Try importing a screenshot instead.",
  },
  payload_too_large: { ar: "الملف كبير جدًا.", en: "The file is too large." },
  internal: { ar: "حدث خطأ غير متوقع.", en: "Something went wrong." },
};

const RETRYABLE: ReadonlySet<ErrorCode> = new Set([
  "stale_request",
  "rate_limited",
  "ai_unavailable",
  "ai_invalid_output",
  "fetch_failed",
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
