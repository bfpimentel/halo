import { Box, Surface, screens, type NativeNode } from "halo";
import { signal } from "halo/signals";

const shift = signal(0);
(globalThis as any).__test = { shift: (points: number) => shift.set(points) };
let button: NativeNode | undefined;

export default () => (
  <>
    <Surface
      screen={screens()[0]}
      anchor={["top", "left"]}
      size={{ width: 400, height: 40 }}
      input="interactive"
    >
      <Box style={{ flexDirection: "row" }}>
        <Box style={{ width: () => shift() }} />
        <Box
          ref={(node) => (button = node)}
          style={{ width: 40, height: 40, background: "#ffffff" }}
        />
      </Box>
    </Surface>
    <Surface
      screen={screens()[0]}
      size={{ width: 100, height: 60 }}
      attach={() => ({ to: button, side: "below", offset: 4 })}
    >
      <Box style={{ background: "#000000" }} />
    </Surface>
  </>
);
