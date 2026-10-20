// <Shape>: a CPU ring whose strokeEnd animates with a spring, with its percentage overlaid in the middle
// (position: "absolute"), a CPU history sparkline, and a plain SVG path.

import { Box, Shape, Surface, Text, ring, sparkline, type WidgetProps } from "halo";
import { system } from "halo/services";
import { effect, signal, untrack } from "halo/signals";

const muted = "#9399b2";
const foreground = "#cdd6f4";
const accent = "#89b4fa";
const green = "#a6e3a1";
const heart = "M 50 88 L 12 50 A 22 22 0 0 1 50 18 A 22 22 0 0 1 88 50 Z";

function Cpu() {
  const history = signal<number[]>([]);
  effect(() => {
    const cpu = system.cpu(1000);
    if (cpu !== undefined)
      untrack(() => history.update((list) => [...list, cpu].slice(-40)));
  });
  const percent = () => Math.round((system.cpu(1000) ?? 0) * 100);

  return (
    <Box style={{ gap: 12 }}>
      <Box style={{ flexDirection: "row", align: "center", gap: 14 }}>
        <Box style={{ width: 56, height: 56 }}>
          <Shape
            path={ring()}
            style={{
              width: 56,
              height: 56,
              fill: "transparent",
              stroke: accent,
              track: "#313244",
              strokeWidth: 6,
              lineCap: "round",
              strokeEnd: () => system.cpu(1000) ?? 0,
              transition: { strokeEnd: { curve: "spring" } },
            }}
          />
          <Box
            style={{
              position: "absolute",
              top: 0,
              right: 0,
              bottom: 0,
              left: 0,
              justify: "center",
              align: "center",
            }}
          >
            <Text style={{ fontSize: 13, fontWeight: "bold", color: foreground }}>
              {() => `${percent()}%`}
            </Text>
          </Box>
        </Box>
        <Box style={{ gap: 2, grow: 1 }}>
          <Text style={{ fontSize: 12, color: muted }}>CPU</Text>
          <Text style={{ fontSize: 12, color: foreground }}>last 40 s below</Text>
        </Box>
        <Shape
          path={heart}
          style={{
            width: 32,
            height: 32,
            fill: "transparent",
            stroke: "#f38ba8",
            strokeWidth: 2,
            lineJoin: "round",
          }}
        />
      </Box>
      <Shape
        path={() => sparkline(history(), { min: 0, area: true })}
        fit="stretch"
        style={{
          height: 36,
          fill: "#a6e3a133",
          stroke: green,
          strokeWidth: 1.5,
          lineJoin: "round",
        }}
      />
    </Box>
  );
}

export default ({ screen }: WidgetProps) => (
  <Surface
    screen={screen}
    anchor={["top", "right"]}
    margins={[48, 16, 0, 0]}
    layer="aboveMenu"
  >
    <Box style={{ width: 240, padding: 16, background: "#1e1e2ef0", radius: 14 }}>
      <Cpu />
    </Box>
  </Surface>
);
