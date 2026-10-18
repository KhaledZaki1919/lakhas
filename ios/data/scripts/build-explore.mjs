// Builds the bundled Explore library (ADR-026) from the curated dish list and the food DB:
//   ios/LakhasKit/Sources/LakhasKit/Resources/Explore/dishes.json
// Run: node ios/data/scripts/build-explore.mjs   (after build-food-db.mjs when foods change)
// Each ingredient takes its names and per-100 g values from foods.json, so a dish's calories
// and macros are the bundled DB's numbers (grams × per-100 g), never typed by hand.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dishes } from "../explore/dishes.mjs";

const root = new URL("../../", import.meta.url);
const foodsFile = new URL("LakhasKit/Sources/LakhasKit/Resources/FoodDB/foods.json", root);
const foods = new Map(JSON.parse(readFileSync(foodsFile, "utf8")).foods.map((f) => [f.id, f]));

const MEALS = new Set(["breakfast", "lunch", "dinner", "snack"]);
const GOALS = new Set(["lose", "maintain", "gain"]);
const CATEGORIES = new Set([
  "beans", "eggs", "dairy", "bread", "rice", "stew", "grill", "fish",
  "salad", "soup", "pasta", "sweet", "fruit", "snack", "drink",
]);
const MIN_DISHES = 60;

const errors = [];
const ids = new Set();
const out = dishes.map((dish, index) => {
  if (ids.has(dish.id)) errors.push(`duplicate id ${dish.id}`);
  ids.add(dish.id);
  if (!dish.nameAr || !dish.nameEn) errors.push(`${dish.id}: missing name`);
  if (!CATEGORIES.has(dish.category)) errors.push(`${dish.id}: unknown category ${dish.category}`);
  if (!dish.meals?.length || dish.meals.some((m) => !MEALS.has(m))) errors.push(`${dish.id}: bad meal types`);
  if (!dish.goals?.length || dish.goals.some((g) => !GOALS.has(g))) errors.push(`${dish.id}: bad goals`);
  if (!dish.ingredients?.length) errors.push(`${dish.id}: no ingredients`);

  const ingredients = dish.ingredients.map((item) => {
    const food = foods.get(item.food);
    if (!food) {
      errors.push(`${dish.id}: unknown food ${item.food}`);
      return null;
    }
    if (!(item.grams > 0 && item.grams <= 1000)) errors.push(`${dish.id}: bad grams for ${item.food}`);
    if (!item.measureAr || !item.measureEn) errors.push(`${dish.id}: missing measure for ${item.food}`);
    return {
      foodId: food.id,
      nameAr: food.nameAr,
      nameEn: food.nameEn,
      grams: item.grams,
      measureAr: item.measureAr,
      measureEn: item.measureEn,
      per100: food.per100,
    };
  }).filter(Boolean);

  const kcal = ingredients.reduce((sum, i) => sum + (i.per100.kcal * i.grams) / 100, 0);
  if (kcal < 50 || kcal > 1500) errors.push(`${dish.id}: ${Math.round(kcal)} kcal per serving looks wrong`);

  return {
    id: dish.id,
    nameAr: dish.nameAr,
    nameEn: dish.nameEn,
    aliasesAr: dish.aliasesAr ?? [],
    aliasesEn: dish.aliasesEn ?? [],
    category: dish.category,
    mealTypes: dish.meals,
    goals: dish.goals,
    servings: dish.servings ?? 1,
    order: index,
    ingredients,
  };
});

if (out.length < MIN_DISHES) errors.push(`only ${out.length} dishes (need ${MIN_DISHES})`);
if (errors.length) throw new Error(errors.join("\n"));

const outDir = new URL("LakhasKit/Sources/LakhasKit/Resources/Explore/", root);
mkdirSync(outDir, { recursive: true });
writeFileSync(new URL("dishes.json", outDir), JSON.stringify({ version: 1, dishes: out }) + "\n");

const count = (key, value) => out.filter((d) => d[key].includes(value)).length;
console.log(`dishes.json: ${out.length} dishes`);
console.log(`  meals: ${[...MEALS].map((m) => `${m} ${count("mealTypes", m)}`).join(", ")}`);
console.log(`  goals: ${[...GOALS].map((g) => `${g} ${count("goals", g)}`).join(", ")}`);
for (const d of out) {
  const t = d.ingredients.reduce((s, i) => {
    for (const k of ["kcal", "protein", "carbs", "fat"]) s[k] += (i.per100[k] * i.grams) / 100;
    return s;
  }, { kcal: 0, protein: 0, carbs: 0, fat: 0 });
  console.log(`  ${d.id.padEnd(26)} ${String(Math.round(t.kcal)).padStart(5)} kcal  P${Math.round(t.protein)} C${Math.round(t.carbs)} F${Math.round(t.fat)}  ${d.goals.join("/")}`);
}
