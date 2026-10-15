import { Box, Image, PerScreen, Surface, Text, type ScreenInfo } from "halo";
import { battery, clock } from "halo/services";
import { signal } from "halo/signals";
import { LoadGraph } from "@/demo/load";

const surface = "#1e1e2ee0";
const foreground = "#cdd6f4";
const muted = "#9399b2";
const accent = "#89b4fa";

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

function TopBar(props: { screen: ScreenInfo }) {
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

function DesktopClock(props: { screen: ScreenInfo }) {
  return (
    <Surface
      screen={props.screen}
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
          {clock.format("HH:mm")}
        </Text>
        <Text style={{ fontSize: 13, color: muted }}>{clock.format("EEEE, d MMMM")}</Text>
      </Box>
    </Surface>
  );
}

function Launcher(props: { screen: ScreenInfo }) {
  return (
    <Surface
      screen={props.screen}
      anchor={["left"]}
      margins={[0, 0, 0, 8]}
      size={{ width: 56, height: 164 }}
      layer="aboveMenu"
    >
      <Box
        style={{
          justify: "center",
          align: "center",
          gap: 8,
          background: surface,
          radius: 14,
        }}
      >
        {["com.apple.finder", "com.apple.Safari", "com.apple.Terminal"].map((app) => (
          <Image app={app} size={40} />
        ))}
      </Box>
    </Surface>
  );
}

function Osd(props: { screen: ScreenInfo }) {
  const visible = signal(true);
  setTimeout(() => visible.set(false), 3000);
  return (
    <Surface
      screen={props.screen}
      size={{ width: 180, height: 180 }}
      layer="overlay"
      visible={visible}
    >
      <Box
        style={{
          justify: "center",
          align: "center",
          gap: 14,
          background: surface,
          radius: 24,
        }}
      >
        <Image symbol="speaker.wave.2.fill" size={56} color={foreground} />
        <Text style={{ fontSize: 15, fontWeight: "medium", color: muted }}>halo</Text>
      </Box>
    </Surface>
  );
}

function Load(props: { screen: ScreenInfo }) {
  return (
    <Surface
      screen={props.screen}
      anchor={["top", "right"]}
      margins={[48, 8, 0, 0]}
      size={{ width: 220, height: 96 }}
      layer="aboveMenu"
    >
      <LoadGraph />
    </Surface>
  );
}

export default () => (
  <PerScreen>
    {(screen) => (
      <>
        <TopBar screen={screen} />
        <DesktopClock screen={screen} />
        <Launcher screen={screen} />
        <Osd screen={screen} />
        <Load screen={screen} />
      </>
    )}
  </PerScreen>
);
