import { Box, Surface, type WidgetProps } from "halo";
import { signal } from "halo/signals";

const log: string[] = [];
const shown = signal(true);
type Input = "passthrough" | "hover" | "interactive" | "keyboard";
const input = signal<Input>("interactive");
const version = signal(0);
(globalThis as any).__test = {
  log,
  hide: () => shown.set(false),
  setInput: (policy: Input) => input.set(policy),
  rerender: () => version.update((v) => v + 1),
};

// 300×100 surface: hover boxes "a" (re-rendered as "a1", "a2"…) and "b", then 100 points of empty space.
export default ({ screen }: WidgetProps) => (
  <Surface screen={screen} anchor={["top", "left"]} input={input} visible={shown}>
    <Box style={{ flexDirection: "row", width: 300, height: 100 }}>
      {() => {
        const name = version() ? `a${version()}` : "a";
        return (
          <Box
            style={{ width: 100, height: 100 }}
            onHover={(on) => log.push(`${name} ${on}`)}
          />
        );
      }}
      <Box style={{ width: 100, height: 100 }} onHover={(on) => log.push(`b ${on}`)} />
    </Box>
  </Surface>
);
