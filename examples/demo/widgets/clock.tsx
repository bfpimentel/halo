import { Box, Surface, Text, defineWidget, type Edge } from "halo";
import { clock } from "halo/services";
import { foreground, muted, surface } from "@/demo/theme";

const corners: Record<string, Edge[]> = {
  "top-left": ["top", "left"],
  "top-right": ["top", "right"],
  "bottom-left": ["bottom", "left"],
  "bottom-right": ["bottom", "right"],
};

export default defineWidget({
  props: {
    time: { type: "string", default: "HH:mm", label: "Time format" },
    date: { type: "string", default: "EEEE, d MMMM", label: "Date format" },
    corner: {
      type: "select",
      options: ["top-left", "top-right", "bottom-left", "bottom-right"],
      default: "bottom-right",
      label: "Corner",
    },
  },
  render: ({ screen, props }) => (
    <Surface
      screen={screen}
      anchor={corners[props.corner]}
      margins={24}
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
          {clock.format(props.time)}
        </Text>
        <Text style={{ fontSize: 13, color: muted }}>{clock.format(props.date)}</Text>
      </Box>
    </Surface>
  ),
});
