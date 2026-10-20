import { Box, Image, Surface, Text, type WidgetProps } from "halo";
import { battery, clock } from "halo/services";
import { accent, foreground, muted, surface } from "@/demo/theme";

function Workspace(props: { name: string; active?: boolean }) {
  return (
    <Box
      style={{
        padding: [2, 7],
        radius: 5,
        background: props.active ? accent : "transparent",
      }}
    >
      <Text
        style={{
          fontSize: 12,
          fontWeight: "semibold",
          color: props.active ? "#1e1e2e" : muted,
        }}
      >
        {props.name}
      </Text>
    </Box>
  );
}

export default function TopBar({ screen }: WidgetProps) {
  return (
    <Surface
      screen={screen}
      anchor={["top", "left", "right"]}
      margins={[4, 8, 0, 8]}
      size={{ height: 32 }}
      layer="belowMenu"
      avoid={["menuBar", "notch"]}
    >
      <Box
        style={{
          flexDirection: "row",
          justify: "space-between",
          align: "center",
          padding: [0, 10],
          background: surface,
          radius: 8,
        }}
      >
        <Box style={{ flexDirection: "row", align: "center", gap: 6 }}>
          <Image symbol="square.grid.2x2" size={14} color={accent} />
          <Workspace name="1" active />
          <Workspace name="2" />
          <Workspace name="3" />
        </Box>
        <Box style={{ flexDirection: "row", align: "center", gap: 8 }}>
          <Image symbol="battery.75percent" size={16} color={foreground} />
          <Text style={{ fontSize: 13, fontWeight: "medium", color: foreground }}>
            {() => `${battery.percent() ?? "–"}%`}
          </Text>
          <Text style={{ fontSize: 13, fontWeight: "medium", color: foreground }}>
            {clock.format("EEE d MMM  HH:mm")}
          </Text>
        </Box>
      </Box>
    </Surface>
  );
}
