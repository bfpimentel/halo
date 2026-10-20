import { Box, Surface, Text, type WidgetProps } from "halo";
import { clock } from "halo/services";
import { computed, signal } from "halo/signals";

const accent = "#89b4fa";
const muted = "#9399b2";

function Showcase() {
  const ticks = signal(0);
  const progress = signal(0);
  setInterval(() => ticks.update((n) => n + 1), 500);
  setInterval(() => progress.update((p) => (p + 2) % 102), 50);

  const even = computed(() => ticks() % 2 === 0);
  const dots = computed(() => ticks() % 9);

  return (
    <Box style={{ padding: 18, gap: 14, background: "#1e1e2ef0", radius: 18 }}>
      <Box style={{ flexDirection: "row", justify: "space-between", align: "center" }}>
        <Text style={{ fontSize: 13, fontWeight: "semibold", color: muted }}>
          SIGNALS
        </Text>
        <Text style={{ fontSize: 13, color: muted }}>{clock.format("HH:mm:ss")}</Text>
      </Box>

      <Box style={{ flexDirection: "row", align: "center", gap: 12 }}>
        <Text
          style={{
            fontSize: 34,
            fontWeight: "bold",
            color: () => (even() ? accent : "#f9e2af"),
          }}
        >
          {() => String(ticks())}
        </Text>
        <Text style={{ fontSize: 14, color: muted }}>
          {() => (even() ? "even" : "odd")}
        </Text>
      </Box>

      <Box style={{ height: 8, background: "#313244", radius: 4 }}>
        <Box
          style={{
            height: 8,
            width: () => `${Math.min(progress(), 100)}%`,
            background: accent,
            radius: 4,
          }}
        />
      </Box>

      <Box style={{ flexDirection: "row", gap: 6, height: 12 }}>
        {() =>
          Array.from({ length: dots() }, () => (
            <Box style={{ width: 12, height: 12, radius: 6, background: accent }} />
          ))
        }
      </Box>
    </Box>
  );
}

export default ({ screen }: WidgetProps) => (
  <Surface screen={screen} size={{ width: 360, height: 210 }} layer="aboveMenu">
    <Showcase />
  </Surface>
);
