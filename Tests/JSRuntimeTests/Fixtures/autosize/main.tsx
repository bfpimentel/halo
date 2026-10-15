import { Box, Surface, screens } from "halo";
import { signal } from "halo/signals";

const rows = signal(1);
(globalThis as any).__test = { setRows: (count: number) => rows.set(count) };

export default () => (
  <Surface name="auto" screen={screens()[0]} anchor={["top"]} input="interactive">
    <Box style={{ padding: 20 }}>
      <Box style={{ width: 100, gap: 4, background: "#222222" }}>
        {() => Array.from({ length: rows() }, () => <Box style={{ height: 10 }} />)}
      </Box>
    </Box>
  </Surface>
);
