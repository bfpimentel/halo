import { Box, Image, PerScreen, Surface, Text } from "halo";
import { clock } from "halo/services";
import { signal } from "halo/signals";

const items = signal([1, 2, 3]);
const minutes = clock.format("HH:mm");
setInterval(() => minutes(), 60_000);
(globalThis as any).__test = {
  setItems: (count: number) => items.set(Array.from({ length: count }, (_, i) => i)),
};

export default () => (
  <PerScreen>
    {(screen) => {
      setInterval(() => {}, 60_000);
      return (
        <Surface screen={screen} anchor={["top"]} size={{ width: 200, height: 30 }}>
          <Box style={{ flexDirection: "row", gap: 4 }}>
            <Text>{clock.format("HH:mm:ss")}</Text>
            {() => items().map((item) => <Text>{String(item)}</Text>)}
            <Image symbol="star" />
          </Box>
        </Surface>
      );
    }}
  </PerScreen>
);
