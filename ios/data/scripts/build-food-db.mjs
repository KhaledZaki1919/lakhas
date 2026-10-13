// Merges the USDA subset and the curated Egyptian/Arab dishes into the bundled food DB:
//   ios/LakhasKit/Sources/LakhasKit/Resources/FoodDB/foods.json
// Run: node ios/data/scripts/build-food-db.mjs   (after build-usda-subset.mjs when USDA changes)
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { DISHES } from "../foods/egyptian-dishes.mjs";

const root = new URL("../../", import.meta.url);
const usda = JSON.parse(readFileSync(new URL("data/foods/usda-subset.json", root), "utf8"));

// Common portions for USDA foods: [labelAr, labelEn, grams].
const USDA_PORTIONS = {
  "usda-rice-white-cooked": [["كوب", "cup", 158], ["طبق", "plate", 250]],
  "usda-rice-brown-cooked": [["كوب", "cup", 195]],
  "usda-pasta-cooked": [["كوب", "cup", 140], ["طبق", "plate", 250]],
  "usda-pita-white": [["رغيف", "loaf", 60]],
  "usda-pita-wholewheat": [["رغيف", "loaf", 64]],
  "usda-bread-white": [["شريحة", "slice", 28]],
  "usda-bread-wholewheat": [["شريحة", "slice", 32]],
  "usda-croissant": [["قطعة", "piece", 57]],
  "usda-oats-dry": [["نصف كوب", "1/2 cup", 40]],
  "usda-egg-raw": [["بيضة", "egg", 50]],
  "usda-egg-boiled": [["بيضة", "egg", 50]],
  "usda-egg-fried": [["بيضة", "egg", 46]],
  "usda-egg-omelet": [["بيضتان", "2 eggs", 120]],
  "usda-milk-whole": [["كوب", "cup", 244]],
  "usda-milk-lowfat": [["كوب", "cup", 244]],
  "usda-milk-skim": [["كوب", "cup", 245]],
  "usda-yogurt-plain": [["علبة", "cup", 170]],
  "usda-yogurt-greek": [["علبة", "cup", 170]],
  "usda-cheese-feta": [["قطعة", "piece", 30]],
  "usda-cheese-mozzarella": [["شريحة", "slice", 28]],
  "usda-cheese-cheddar": [["شريحة", "slice", 28]],
  "usda-cheese-processed": [["مثلث", "wedge", 17]],
  "usda-butter": [["ملعقة كبيرة", "tablespoon", 14]],
  "usda-ghee": [["ملعقة كبيرة", "tablespoon", 13]],
  "usda-chicken-breast-roasted": [["نصف صدر", "half breast", 172]],
  "usda-banana": [["موزة متوسطة", "medium banana", 118]],
  "usda-apple": [["تفاحة متوسطة", "medium apple", 182]],
  "usda-orange": [["برتقالة", "orange", 131]],
  "usda-tangerine": [["يوسفية", "mandarin", 88]],
  "usda-mango": [["مانجاية", "mango", 336]],
  "usda-guava": [["جوافة", "guava", 55]],
  "usda-dates-medjool": [["بلحة", "date", 24]],
  "usda-dates-deglet": [["بلحة", "date", 7], ["٧ بلحات", "7 dates", 50]],
  "usda-figs": [["تينة", "fig", 50]],
  "usda-tomato": [["طماطماية", "tomato", 123]],
  "usda-cucumber": [["خيارة", "cucumber", 100]],
  "usda-olive-oil": [["ملعقة كبيرة", "tablespoon", 13.5]],
  "usda-sunflower-oil": [["ملعقة كبيرة", "tablespoon", 13.6]],
  "usda-tahini": [["ملعقة كبيرة", "tablespoon", 15]],
  "usda-honey": [["ملعقة كبيرة", "tablespoon", 21]],
  "usda-sugar": [["ملعقة صغيرة", "teaspoon", 4.2]],
  "usda-tea-brewed": [["كوب", "cup", 240]],
  "usda-coffee-brewed": [["كوب", "cup", 240]],
  "usda-cola": [["علبة", "can", 330]],
  "usda-french-fries": [["علبة متوسطة", "medium portion", 117]],
  "usda-tuna-oil": [["علبة", "can", 120]],
  "usda-sardine-canned": [["علبة", "can", 92]],
};

const round = (x) => Math.round(x * 10) / 10;
const foods = [];

for (const [id, nameAr, nameEn, aliasesAr, aliasesEn, category, [protein, carbs, fat], portions] of DISHES) {
  foods.push({
    id: `eg-${id}`,
    nameAr, nameEn, aliasesAr, aliasesEn, category,
    per100: { kcal: Math.round(4 * protein + 4 * carbs + 9 * fat), protein, carbs, fat },
    portions: portions.map(([labelAr, labelEn, grams]) => ({ labelAr, labelEn, grams })),
    source: "curated_estimate",
    nameArSource: "human",
  });
}

for (const f of usda) {
  foods.push({
    id: f.id,
    nameAr: f.nameAr, nameEn: f.nameEn, aliasesAr: [], aliasesEn: [], category: f.category,
    per100: { kcal: Math.round(f.per100.kcal), protein: round(f.per100.protein), carbs: round(f.per100.carbs), fat: round(f.per100.fat) },
    portions: (USDA_PORTIONS[f.id] ?? []).map(([labelAr, labelEn, grams]) => ({ labelAr, labelEn, grams })),
    source: "usda",
    sourceRef: `FDC ${f.fdcId}`,
    nameArSource: f.nameArSource,
  });
}

// Validation
const errors = [];
const ids = new Set();
for (const f of foods) {
  if (ids.has(f.id)) errors.push(`duplicate id ${f.id}`);
  ids.add(f.id);
  const { protein, carbs, fat, kcal } = f.per100;
  if (protein + carbs + fat > 100.5) errors.push(`${f.id}: macros exceed 100 g`);
  if (kcal < 0 || kcal > 900) errors.push(`${f.id}: kcal out of range`);
  if (!f.nameAr || !f.nameEn) errors.push(`${f.id}: missing name`);
  for (const p of f.portions) if (!(p.grams > 0)) errors.push(`${f.id}: bad portion`);
}
for (const id of Object.keys(USDA_PORTIONS)) if (!ids.has(id)) errors.push(`portion for unknown food ${id}`);
if (errors.length) throw new Error(errors.join("\n"));

const outDir = new URL("LakhasKit/Sources/LakhasKit/Resources/FoodDB/", root);
mkdirSync(outDir, { recursive: true });
writeFileSync(new URL("foods.json", outDir), JSON.stringify({ version: 1, foods }) + "\n");
const curated = foods.filter((f) => f.source === "curated_estimate").length;
console.log(`foods.json: ${foods.length} foods (${curated} Egyptian/Arab dishes, ${foods.length - curated} USDA)`);
