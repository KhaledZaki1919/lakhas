/**
 * Daily targets (PROJECT_PROMPT.md §6), mirroring ios/LakhasKit NutritionMath.
 * Both are tested against shared/test-vectors/nutrition.json.
 */
export type Sex = "male" | "female";
export type ActivityLevel = "sedentary" | "light" | "active" | "veryActive";
export type Goal = "lose" | "maintain" | "gain";

export interface BodyProfile {
  sex: Sex;
  age: number;
  heightCm: number;
  weightKg: number;
  activity: ActivityLevel;
  goal: Goal;
  paceKgPerWeek: number;
  goalWeightKg?: number;
}

export interface DailyTargets {
  bmr: number;
  tdee: number;
  calories: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  waterMl: number;
  floorApplied: boolean;
  fatReduced: boolean;
}

const ACTIVITY_FACTOR: Record<ActivityLevel, number> = {
  sedentary: 1.2,
  light: 1.375,
  active: 1.55,
  veryActive: 1.725,
};
const PROTEIN_PER_KG: Record<Goal, number> = { lose: 2.0, maintain: 1.6, gain: 1.8 };

export function bmr(p: Pick<BodyProfile, "sex" | "weightKg" | "heightCm" | "age">): number {
  const base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age;
  return p.sex === "male" ? base + 5 : base - 161;
}

export function bmi(weightKg: number, heightCm: number): number {
  const m = heightCm / 100;
  return weightKg / (m * m);
}

export function bmiCategory(value: number): "underweight" | "normal" | "overweight" | "obese" {
  if (value < 18.5) return "underweight";
  if (value < 25) return "normal";
  if (value < 30) return "overweight";
  return "obese";
}

export function proteinReferenceWeight(p: BodyProfile): number {
  if (bmi(p.weightKg, p.heightCm) < 30) return p.weightKg;
  const m = p.heightCm / 100;
  return p.goalWeightKg ?? 25 * m * m;
}

export function waterMl(weightKg: number, activity: ActivityLevel): number {
  const bonus = activity === "active" || activity === "veryActive" ? 1.1 : 1;
  return Math.round((35 * weightKg * bonus) / 250) * 250;
}

export function dailyTargets(p: BodyProfile): DailyTargets {
  const basal = bmr(p);
  const tdee = basal * ACTIVITY_FACTOR[p.activity];
  const pace = p.goal === "maintain" ? 0 : p.paceKgPerWeek;
  const sign = p.goal === "lose" ? -1 : p.goal === "gain" ? 1 : 0;
  const adjusted = tdee + sign * (pace / 0.25) * 250;
  const floor = Math.max(basal, p.sex === "female" ? 1200 : 1500);
  const calories = Math.max(adjusted, floor);

  const proteinG = PROTEIN_PER_KG[p.goal] * proteinReferenceWeight(p);
  const proteinKcal = proteinG * 4;
  let fatKcal = 0.27 * calories;
  let fatReduced = false;
  if (calories - proteinKcal - fatKcal < 0) {
    fatKcal = Math.max(0.2 * calories, calories - proteinKcal);
    fatReduced = true;
  }
  const carbsKcal = Math.max(0, calories - proteinKcal - fatKcal);

  return {
    bmr: basal,
    tdee,
    calories: Math.round(calories),
    proteinG: Math.round(proteinG),
    carbsG: Math.round(carbsKcal / 4),
    fatG: Math.round(fatKcal / 9),
    waterMl: waterMl(p.weightKg, p.activity),
    floorApplied: adjusted < floor,
    fatReduced,
  };
}
