// A bar showing AeroSpace workspaces per display. Add to your aerospace.toml (use halo's absolute path if
// AeroSpace's PATH doesn't include it):
//
//   exec-on-workspace-change = ['/bin/bash', '-c',
//     'halo trigger aerospace.workspace focused=$AEROSPACE_FOCUSED_WORKSPACE prev=$AEROSPACE_PREV_WORKSPACE']
//   on-focus-changed = ['exec-and-forget halo trigger aerospace.focus']   # optional: keeps "empty" state fresh

import { Box, PerScreen, Surface, Text, type ScreenInfo } from "halo";
import { aerospace, type Workspace } from "halo/aerospace";
import { clock } from "halo/services";

const surface = "#1e1e2ee0";
const foreground = "#cdd6f4";
const muted = "#6c7086";
const accent = "#89b4fa";

const spaces = aerospace();
const time = clock.format("EEE d MMM  HH:mm");

function Pill(props: { workspace: Workspace }) {
  const { focused, empty, name } = props.workspace;
  return (
    <Box
      style={{ padding: [2, 8], radius: 5, background: focused ? accent : "transparent" }}
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

function Bar(props: { screen: ScreenInfo }) {
  const workspaces = spaces.on(props.screen);
  return (
    <Surface
      screen={props.screen}
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
          padding: [0, 8],
          background: surface,
          radius: 8,
        }}
      >
        <Box style={{ flexDirection: "row", align: "center", gap: 4 }}>
          {() => workspaces().map((workspace) => <Pill workspace={workspace} />)}
        </Box>
        <Text style={{ fontSize: 13, fontWeight: "medium", color: foreground }}>
          {time}
        </Text>
      </Box>
    </Surface>
  );
}

export default () => <PerScreen>{(screen) => <Bar screen={screen} />}</PerScreen>;
