import { describe, expect, it } from "vitest";
import vectors from "../../shared/test-vectors/nutrition.json";
import { type BodyProfile, bmi, bmiCategory, dailyTargets } from "../src/lib/nutrition";

describe("nutrition math matches shared/test-vectors/nutrition.json", () => {
  it.each(vectors.cases)("$name", ({ profile, expected }) => {
    const p = profile as BodyProfile;
    const t = dailyTargets(p);
    expect(Math.round(t.bmr * 100) / 100).toBe(expected.bmr);
    expect(Math.round(t.tdee * 100) / 100).toBe(expected.tdee);
    expect({
      calories: t.calories,
      proteinG: t.proteinG,
      carbsG: t.carbsG,
      fatG: t.fatG,
      waterMl: t.waterMl,
      floorApplied: t.floorApplied,
      fatReduced: t.fatReduced,
    }).toEqual({
      calories: expected.calories,
      proteinG: expected.proteinG,
      carbsG: expected.carbsG,
      fatG: expected.fatG,
      waterMl: expected.waterMl,
      floorApplied: expected.floorApplied,
      fatReduced: expected.fatReduced,
    });
    expect(bmiCategory(bmi(p.weightKg, p.heightCm))).toBe(expected.bmiCategory);
  });
});
