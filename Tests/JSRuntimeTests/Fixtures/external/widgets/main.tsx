import { effect, externalSignal } from "halo/signals";

const workspace = externalSignal("ws", {
  initial: "none",
  parse: (payload) => payload.focused,
});
const seen: string[] = [];
effect(() => seen.push(workspace() ?? "undefined"));
(globalThis as any).__test = { seen };

export default () => null;
