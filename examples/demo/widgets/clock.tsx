import { Box, Surface, Text, type WidgetProps } from "halo";
import { clock } from "halo/services";
import { foreground, muted, surface } from "@/demo/theme";

export default function DesktopClock({
  screen,
  props,
}: WidgetProps<{ time?: string; date?: string }>) {
  return (
    <Surface
      screen={screen}
      anchor={["bottom", "right"]}
      margins={[0, 24, 24, 0]}
      size={{ width: 240, height: 96 }}
      layer="desktop"
    >
      <Box
        style={{
          justify: "center",
          padding: [0, 18],
          gap: 2,
          background: surface,
          radius: 16,
        }}
      >
        <Text style={{ fontSize: 40, fontWeight: "semibold", color: foreground }}>
          {clock.format(props.time ?? "HH:mm")}
        </Text>
        <Text style={{ fontSize: 13, color: muted }}>
          {clock.format(props.date ?? "EEEE, d MMMM")}
        </Text>
      </Box>
    </Surface>
  );
}
