import { Hono } from "hono";
import type { ApiEnv } from "../types";

/**
 * Public pages linked from the app (ADR-027 §10): /privacy and /terms, Arabic by default,
 * `?lang=en` for English. Plain HTML, no scripts, no trackers.
 */
export const pages = new Hono<ApiEnv>();

type Lang = "ar" | "en";

interface Section {
  title: string;
  body: string[];
}

const UPDATED = "2026-10-19";

const PRIVACY: Record<Lang, { title: string; intro: string; sections: Section[] }> = {
  ar: {
    title: "سياسة الخصوصية — لخّص",
    intro:
      "لخّص تطبيق شخصي لتتبع السعرات. معظم بياناتك تبقى على جهازك فقط. هذه الصفحة تشرح بالضبط ما يخرج من جهازك وإلى أين.",
    sections: [
      {
        title: "على جهازك",
        body: [
          "وجباتك وصورك ووصفاتك ومنتجاتك وأهدافك محفوظة على جهازك، محمية بتشفير iOS ومستبعدة من نسخ iCloud.",
          "مفتاح الذكاء الاصطناعي الذي تدخله محفوظ في سلسلة المفاتيح (Keychain) على هذا الجهاز فقط، ولا يُرسل إلى خادمنا أبدًا.",
        ],
      },
      {
        title: "الذكاء الاصطناعي",
        body: [
          "عند تحليل صورة أو نص، يرسل التطبيق الطلب مباشرة من جهازك إلى مزوّد الذكاء الاصطناعي الذي اخترته (Anthropic أو OpenAI أو Google أو OpenRouter) بمفتاحك أنت، وتخضع لشروط ذلك المزوّد. خادمنا لا يرى هذه الطلبات.",
          "تُصغَّر الصور وتُحذف منها بيانات الموقع قبل الإرسال.",
        ],
      },
      {
        title: "الحساب (اختياري)",
        body: [
          "الحساب اختياري ويلزم فقط للنسخ الاحتياطي والتصويت ومشاركة المنتجات. نحفظ: بريدك الإلكتروني، وقيمة تحقق مشتقة من كلمة المرور (كلمة المرور نفسها لا تغادر جهازك أبدًا)، وأجهزتك المسجّلة وتواريخ آخر استخدام.",
          "النسخة الاحتياطية مشفّرة بالكامل على جهازك قبل رفعها. لا نستطيع قراءتها. إذا فقدت كلمة المرور ورمز الاسترداد معًا فلا يمكن لأحد، ولا نحن، فتحها. صور الوجبات لا تُضمَّن في النسخة الاحتياطية.",
          "إذا شاركت منتجًا بالباركود، نحفظ بياناته الغذائية فقط (بدون صور) لمراجعتها ثم إتاحتها للمستخدمين الآخرين. يمكنك إيقاف المشاركة من الإعدادات.",
          "تصويتك على الأطباق (👍/👎) محفوظ مع حسابك، وتظهر للآخرين المجاميع فقط.",
        ],
      },
      {
        title: "ما لا نفعله",
        body: [
          "لا إعلانات، ولا أدوات تحليل، ولا تتبع، ولا بيع للبيانات.",
          "عناوين IP لا تُحفظ إلا مشفّرة بدالة تجزئة لمكافحة الإساءة، وتُستخدم حدود للطلبات لحماية الخدمة.",
        ],
      },
      {
        title: "الحذف",
        body: [
          "من الإعدادات ← الحساب ← حذف الحساب: يُحذف حسابك وأجهزتك ونسخك الاحتياطية وتصويتاتك ومنتجاتك قيد المراجعة من خادمنا فورًا. المنتجات التي تمت الموافقة عليها تبقى بدون أي ربط بك.",
          "«احذف بياناتي» يمسح كل شيء من جهازك.",
        ],
      },
    ],
  },
  en: {
    title: "Privacy policy — Lakhas",
    intro:
      "Lakhas is a personal calorie tracker. Most of your data never leaves your phone. This page says exactly what does, and where it goes.",
    sections: [
      {
        title: "On your phone",
        body: [
          "Your meals, photos, recipes, products and goals are stored on your phone, protected by iOS encryption and excluded from iCloud device backups.",
          "The AI key you enter is stored in the Keychain on this phone only. It is never sent to our server.",
        ],
      },
      {
        title: "AI",
        body: [
          "When you analyze a photo or text, the app sends it directly from your phone to the AI provider you chose (Anthropic, OpenAI, Google or OpenRouter), with your own key, under that provider's terms. Our server never sees these requests.",
          "Photos are downscaled and their location data is removed before sending.",
        ],
      },
      {
        title: "Account (optional)",
        body: [
          "An account is optional and only needed for backup, voting and sharing products. We store your email, a verifier derived from your password (the password itself never leaves your phone), and your signed-in devices with when they were last used.",
          "Backups are fully encrypted on your phone before upload. We can't read them. If you lose both your password and your recovery code, nobody, including us, can open them. Meal photos are not included in backups.",
          "If you share a barcode product, we store its nutrition data only (no photos) for review, and then make it available to other users. You can turn sharing off in Settings.",
          "Your dish votes (👍/👎) are stored with your account; others only see totals.",
        ],
      },
      {
        title: "What we don't do",
        body: [
          "No ads, no analytics, no tracking, no selling data.",
          "IP addresses are only kept as keyed hashes, for abuse prevention, and requests are rate-limited to protect the service.",
        ],
      },
      {
        title: "Deletion",
        body: [
          "Settings → Account → Delete account removes your account, devices, backups, votes and pending products from our server immediately. Approved products stay, with no link to you.",
          '"Delete my data" erases everything on your phone.',
        ],
      },
    ],
  },
};

const TERMS: Record<Lang, { title: string; intro: string; sections: Section[] }> = {
  ar: {
    title: "شروط الاستخدام — لخّص",
    intro: "لخّص يُقدَّم كما هو، للاستخدام الشخصي وبدعوة.",
    sections: [
      {
        title: "القيم الغذائية",
        body: [
          "السعرات والعناصر الغذائية تقديرية، سواء جاءت من قاعدة الأطعمة أو من الذكاء الاصطناعي. التطبيق ليس نصيحة طبية؛ استشر مختصًا لأي قرار صحي.",
        ],
      },
      {
        title: "مفتاحك وتكلفته",
        body: [
          "أنت تستخدم مفتاحك الخاص لدى مزوّد الذكاء الاصطناعي وتدفع له مباشرة. تقديرات التكلفة في التطبيق تقريبية.",
        ],
      },
      {
        title: "الحساب والمحتوى",
        body: [
          "حافظ على كلمة المرور ورمز الاسترداد. لا نستطيع استعادة نسخة احتياطية بدونهما.",
          "المنتجات التي تشاركها تُراجع قبل نشرها، ويمكن رفضها أو تعديلها أو حذفها. يمكن إيقاف الحسابات التي تسيء الاستخدام.",
          "الوصفات المستوردة من الروابط للاستخدام الشخصي، ويُحفظ مصدرها.",
        ],
      },
    ],
  },
  en: {
    title: "Terms of use — Lakhas",
    intro: "Lakhas is provided as is, for personal, invite-only use.",
    sections: [
      {
        title: "Nutrition values",
        body: [
          "Calories and macros are estimates, whether they come from the food database or from AI. The app is not medical advice; ask a professional before any health decision.",
        ],
      },
      {
        title: "Your key and its cost",
        body: [
          "You use your own AI provider key and pay that provider directly. Cost estimates in the app are approximate.",
        ],
      },
      {
        title: "Account and content",
        body: [
          "Keep your password and recovery code safe. Without them a backup can't be restored.",
          "Products you share are reviewed before they're published and may be rejected, edited or removed. Accounts that abuse the service may be disabled.",
          "Recipes imported from links are for personal use, and their source is kept.",
        ],
      },
    ],
  },
};

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function render(
  lang: Lang,
  doc: (typeof PRIVACY)["ar"],
  contact: string | undefined,
  path: string,
) {
  const other = lang === "ar" ? "en" : "ar";
  const contactLine = contact
    ? lang === "ar"
      ? `للتواصل: <a href="mailto:${escapeHtml(contact)}">${escapeHtml(contact)}</a>`
      : `Contact: <a href="mailto:${escapeHtml(contact)}">${escapeHtml(contact)}</a>`
    : lang === "ar"
      ? "للتواصل: عبر صاحب الدعوة التي وصلتك."
      : "Contact: through the person who invited you.";
  const sections = doc.sections
    .map(
      (s) =>
        `<h2>${escapeHtml(s.title)}</h2>${s.body.map((p) => `<p>${escapeHtml(p)}</p>`).join("")}`,
    )
    .join("");
  return `<!doctype html>
<html lang="${lang}" dir="${lang === "ar" ? "rtl" : "ltr"}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(doc.title)}</title>
<style>
:root { color-scheme: light dark; --bg: #FBF7F0; --ink: #2A2420; --muted: #6B6158; --primary: #1F7A5A; }
@media (prefers-color-scheme: dark) { :root { --bg: #171412; --ink: #F3EDE4; --muted: #A89E93; --primary: #5CC59B; } }
body { margin: 0; background: var(--bg); color: var(--ink); font: 17px/1.6 -apple-system, system-ui, "SF Arabic", sans-serif; }
main { max-width: 720px; margin: 0 auto; padding: 24px 16px 48px; }
h1 { color: var(--primary); font-size: 28px; } h2 { font-size: 20px; margin-top: 28px; }
.meta, .meta a { color: var(--muted); font-size: 14px; } a { color: var(--primary); }
</style>
</head>
<body><main>
<p class="meta"><a href="${path}?lang=${other}">${other === "en" ? "English" : "العربية"}</a></p>
<h1>${escapeHtml(doc.title)}</h1>
<p>${escapeHtml(doc.intro)}</p>
${sections}
<p class="meta">${contactLine}<br>${lang === "ar" ? "آخر تحديث" : "Last updated"}: ${UPDATED}</p>
</main></body></html>`;
}

function langOfPage(query: string | undefined, accept: string | undefined): Lang {
  if (query === "en" || query === "ar") return query;
  return accept?.toLowerCase().startsWith("en") ? "en" : "ar";
}

for (const [path, doc] of [
  ["/privacy", PRIVACY],
  ["/terms", TERMS],
] as const) {
  pages.get(path, (c) => {
    const lang = langOfPage(c.req.query("lang"), c.req.header("Accept-Language"));
    c.header("Cache-Control", "public, max-age=3600");
    c.header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'");
    return c.html(render(lang, doc[lang], c.env.CONTACT_EMAIL || undefined, path));
  });
}
