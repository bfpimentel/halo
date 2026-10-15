import { describe, expect, test } from "bun:test";
import { cubicBezier, defaultSpring, easing, settled, springStep } from "../src/easing";

describe("easing", () => {
  test("cubic-bezier matches its endpoints and known CSS values", () => {
    const easeOut = easing("ease-out");
    expect(easeOut(0)).toBe(0);
    expect(easeOut(1)).toBe(1);
    expect(easeOut(0.5)).toBeCloseTo(0.6847, 3);
    expect(easing("linear")(0.3)).toBeCloseTo(0.3, 5);
    expect(easing("ease-in-out")(0.5)).toBeCloseTo(0.5, 4);
  });

  test("overshooting curves can leave 0…1", () => {
    const back = cubicBezier(0.34, 1.56, 0.64, 1);
    const peak = Math.max(...Array.from({ length: 50 }, (_, i) => back(i / 49)));
    expect(peak).toBeGreaterThan(1);
  });

  test("a spring settles on its target from any starting velocity", () => {
    let value = 0;
    let velocity = 2000;
    for (let frame = 0; frame < 120 && !settled(value, velocity, 100); frame++) {
      [value, velocity] = springStep(defaultSpring, value, velocity, 100, 1 / 60);
    }
    expect(settled(value, velocity, 100)).toBe(true);
  });

  test("an underdamped spring overshoots before settling", () => {
    const bouncy = { stiffness: 400, damping: 8, mass: 1 };
    let value = 0;
    let velocity = 0;
    let max = 0;
    for (let frame = 0; frame < 60; frame++) {
      [value, velocity] = springStep(bouncy, value, velocity, 1, 1 / 60);
      max = Math.max(max, value);
    }
    expect(max).toBeGreaterThan(1.2);
  });
});
