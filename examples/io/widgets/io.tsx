// Files and processes: a click counter kept across reloads (readFile/writeFile), a note you edit from a terminal
// (watchFile), and live latency from a long-running ping (spawn). Try:
//
//   echo "ship it" > ~/.cache/halo-examples/note.txt

import {
  Box,
  Surface,
  Text,
  readFile,
  spawn,
  watchFile,
  writeFile,
  type WidgetProps,
} from "halo";
import { signal } from "halo/signals";

const folder = "~/.cache/halo-examples";
const muted = "#9399b2";
const foreground = "#cdd6f4";
const accent = "#89b4fa";

function Counter() {
  const clicks = signal(0);
  readFile(`${folder}/clicks.txt`).then(
    (text) => clicks.set(Number(text) || 0),
    () => {}, // first run: nothing saved yet
  );
  const click = () => {
    clicks.update((n) => n + 1);
    writeFile(`${folder}/clicks.txt`, String(clicks()));
  };
  return (
    <Box
      style={{ flexDirection: "row", justify: "space-between", align: "center" }}
      onClick={click}
    >
      <Text style={{ fontSize: 13, color: muted }}>Clicks (saved)</Text>
      <Text style={{ fontSize: 15, fontWeight: "semibold", color: accent }}>
        {() => String(clicks())}
      </Text>
    </Box>
  );
}

function Latency() {
  const ms = signal<number | undefined>(undefined);
  spawn("/sbin/ping", ["-i", "2", "1.1.1.1"], {
    onLine: (line) => {
      const match = line.match(/time=([\d.]+) ms/);
      if (match) ms.set(Number(match[1]));
    },
    onError: () => ms.set(undefined),
  });
  return (
    <Box style={{ flexDirection: "row", justify: "space-between", align: "center" }}>
      <Text style={{ fontSize: 13, color: muted }}>Ping 1.1.1.1</Text>
      <Text style={{ fontSize: 15, fontWeight: "semibold", color: foreground }}>
        {() => (ms() === undefined ? "–" : `${Math.round(ms() ?? 0)} ms`)}
      </Text>
    </Box>
  );
}

function Note() {
  const note = watchFile(`${folder}/note.txt`);
  return (
    <Text style={{ fontSize: 13, color: foreground, lines: 3 }}>
      {() => note()?.trim() || "No note yet: write to ~/.cache/halo-examples/note.txt"}
    </Text>
  );
}

export default ({ screen }: WidgetProps) => (
  <Surface
    screen={screen}
    anchor={["top", "right"]}
    margins={[48, 16, 0, 0]}
    layer="aboveMenu"
    input="interactive"
  >
    <Box
      style={{
        width: 260,
        padding: 16,
        gap: 12,
        background: "#1e1e2ef0",
        radius: 14,
      }}
    >
      <Counter />
      <Latency />
      <Note />
    </Box>
  </Surface>
);
