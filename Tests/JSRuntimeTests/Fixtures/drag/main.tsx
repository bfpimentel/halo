import { Box, PerScreen, Surface } from "halo";
import { signal } from "halo/signals";

const log: string[] = [];
const files = signal<string[] | undefined>(["/tmp/a.txt", "/tmp/b.png"]);
(globalThis as any).__test = { log, clearDraggable: () => files.set(undefined) };

// 200×100 surface: a drop zone at the left half, a draggable item at the right half.
export default () => (
  <PerScreen>
    {(screen) => (
      <Surface screen={screen} anchor={["top", "left"]} input="interactive">
        <Box style={{ flexDirection: "row", width: 200, height: 100 }}>
          <Box
            style={{ width: 100, height: 100 }}
            onDragEnter={(event) => log.push(`enter ${event.files.join(",")}`)}
            onDragLeave={() => log.push("leave")}
            onDrop={(event) =>
              log.push(`drop ${event.files.join(",")} @${event.x},${event.y}`)
            }
          />
          <Box
            style={{ width: 100, height: 100 }}
            draggable={() => (files() ? { files: files() ?? [] } : undefined)}
            onClick={() => log.push("click")}
          />
        </Box>
      </Surface>
    )}
  </PerScreen>
);
