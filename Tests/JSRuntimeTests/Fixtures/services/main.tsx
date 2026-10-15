import { Box, Surface, Text, screens } from "halo";
import { battery } from "halo/services";
import { signal } from "halo/signals";

const shown = signal(true);
(globalThis as any).__test = { show: (value: boolean) => shown.set(value) };

export default () => (
  <Surface screen={screens()[0]} anchor={["top"]}>
    <Box>
      {() => (shown() ? <Text>{() => `${battery.percent() ?? "?"}%`}</Text> : null)}
    </Box>
  </Surface>
);
