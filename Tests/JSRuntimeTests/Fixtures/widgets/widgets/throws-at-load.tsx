import { state } from "@/lib/shared";

state.mounted.push("throws-at-load evaluated");
if (state.evaluations > 0) throw new Error("module-level failure");

export default () => null;
