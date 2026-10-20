export const state = { evaluations: 0, mounted: [] as string[] };
state.evaluations += 1;
(globalThis as any).__test = state;
