// The workspaces AeroSpace shows on each display, the focused one highlighted. Needs the aerospace.toml
// lines from this example's README.

import { Box, Surface, Text, type WidgetProps } from "halo";
import { aerospace, type Workspace } from "@/aerospace/widgets/spaces/aerospace";

const surface = "#1e1e2ee0";
const foreground = "#cdd6f4";
const muted = "#6c7086";
const accent = "#89b4fa";

const spaces = aerospace();

function Pill(props: { workspace: Workspace }) {
  const { focused, empty, name } = props.workspace;
  return (
    <Box
      style={{
        padding: [2, 8],
        radius: 5,
        background: focused ? accent : "transparent",
        transition: { background: 150 },
      }}
    >
      <Text
        style={{
          fontSize: 12,
          fontWeight: "semibold",
          color: focused ? "#1e1e2e" : empty ? muted : foreground,
        }}
      >
        {name}
      </Text>
    </Box>
  );
}

export default function Spaces({ screen }: WidgetProps) {
  const workspaces = spaces.on(screen);
  return (
    <Surface
      screen={screen}
      anchor={["top"]}
      margins={[8, 0, 0, 0]}
      layer="aboveMenu"
      avoid={["menuBar"]}
    >
      <Box
        style={{
          flexDirection: "row",
          align: "center",
          gap: 4,
          padding: 4,
          background: surface,
          radius: 8,
        }}
      >
        {() => workspaces().map((workspace) => <Pill workspace={workspace} />)}
      </Box>
    </Surface>
  );
}
