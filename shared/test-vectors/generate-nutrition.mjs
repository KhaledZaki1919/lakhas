// Regenerates nutrition.json from PROJECT_PROMPT.md §6, written independently of the Swift
// (NutritionMath) and TypeScript (backend/src/lib/nutrition.ts) implementations.
// Run: node shared/test-vectors/generate-nutrition.mjs
import { writeFileSync } from "node:fs";

const FACTORS = { sedentary: 1.2, light: 1.375, active: 1.55, veryActive: 1.725 };
const PROTEIN = { lose: 2.0, maintain: 1.6, gain: 1.8 };

function compute(p) {
  const bmr = 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age + (p.sex === "male" ? 5 : -161);
  const tdee = bmr * FACTORS[p.activity];
  const pace = p.goal === "maintain" ? 0 : p.paceKgPerWeek;
  const adjustment = (pace / 0.25) * 250 * (p.goal === "lose" ? -1 : p.goal === "gain" ? 1 : 0);
  const adjusted = tdee + adjustment;
  const floor = Math.max(bmr, p.sex === "female" ? 1200 : 1500);
  const calories = Math.max(adjusted, floor);

  const m = p.heightCm / 100;
  const bmi = p.weightKg / (m * m);
  const refWeight = bmi >= 30 ? (p.goalWeightKg ?? 25 * m * m) : p.weightKg;
  const proteinG = PROTEIN[p.goal] * refWeight;
  const proteinKcal = proteinG * 4;
  let fatKcal = 0.27 * calories;
  let fatReduced = false;
  if (calories - proteinKcal - fatKcal < 0) {
    fatKcal = Math.max(0.2 * calories, calories - proteinKcal);
    fatReduced = true;
  }
  const carbsKcal = Math.max(0, calories - proteinKcal - fatKcal);

  let water = 35 * p.weightKg;
  if (p.activity === "active" || p.activity === "veryActive") water *= 1.1;

  const category = bmi < 18.5 ? "underweight" : bmi < 25 ? "normal" : bmi < 30 ? "overweight" : "obese";
  return {
    bmr: Math.round(bmr * 100) / 100,
    tdee: Math.round(tdee * 100) / 100,
    calories: Math.round(calories),
    proteinG: Math.round(proteinG),
    carbsG: Math.round(carbsKcal / 4),
    fatG: Math.round(fatKcal / 9),
    waterMl: Math.round(water / 250) * 250,
    floorApplied: adjusted < floor,
    fatReduced,
    bmiCategory: category,
    healthyMinKg: Math.round(18.5 * m * m * 10) / 10,
    healthyMaxKg: Math.round(24.9 * m * m * 10) / 10,
  };
}

const profiles = [
  { name: "man, active, lose 0.5", sex: "male", age: 30, heightCm: 180, weightKg: 80, activity: "active", goal: "lose", paceKgPerWeek: 0.5 },
  { name: "woman, light, maintain", sex: "female", age: 28, heightCm: 165, weightKg: 60, activity: "light", goal: "maintain", paceKgPerWeek: 0 },
  { name: "woman, BMI ≥ 30, floor applies", sex: "female", age: 45, heightCm: 160, weightKg: 95, activity: "sedentary", goal: "lose", paceKgPerWeek: 1.0 },
  { name: "man, very active, gain 0.5", sex: "male", age: 25, heightCm: 175, weightKg: 70, activity: "veryActive", goal: "gain", paceKgPerWeek: 0.5 },
  { name: "man, BMI ≥ 30 with goal weight", sex: "male", age: 40, heightCm: 178, weightKg: 110, activity: "light", goal: "lose", paceKgPerWeek: 0.75, goalWeightKg: 85 },
  { name: "man, underweight, gain 0.25", sex: "male", age: 19, heightCm: 182, weightKg: 58, activity: "sedentary", goal: "gain", paceKgPerWeek: 0.25 },
  { name: "edge: protein crowds out carbs, fat drops to 20%", sex: "female", age: 60, heightCm: 150, weightKg: 120, activity: "sedentary", goal: "lose", paceKgPerWeek: 1.0, goalWeightKg: 200 },
  { name: "man, low floor (1500)", sex: "male", age: 70, heightCm: 160, weightKg: 55, activity: "sedentary", goal: "lose", paceKgPerWeek: 1.0 },
];

const cases = profiles.map(({ name, ...profile }) => ({ name, profile, expected: compute(profile) }));
writeFileSync(
  new URL("./nutrition.json", import.meta.url),
  JSON.stringify({ description: "Daily target vectors (PROJECT_PROMPT.md §6). bmr/tdee rounded to 0.01.", cases }, null, 2) + "\n",
);
console.log(`wrote ${cases.length} cases`);
