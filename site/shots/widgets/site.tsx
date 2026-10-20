// Widgets for the site screenshots (scripts/screenshots.sh captures each named surface's window).

import { Box, Image, Surface, Text, type ScreenInfo, type WidgetProps } from "halo";
import { audio, battery, clock, frontApp, network, system } from "halo/services";

const card = "#1e1e2ef2";
const foreground = "#cdd6f4";
const muted = "#7f849c";
const accent = "#89b4fa";
const apps = [
  ["com.apple.Safari", "Safari", "Applications"],
  ["com.apple.Notes", "Notes", "System Applications"],
  ["com.apple.iCal", "Calendar", "System Applications"],
  ["com.apple.Terminal", "Terminal", "Utilities"],
] as const;

function Bar() {
  return (
    <Box
      style={{
        flexDirection: "row",
        justify: "space-between",
        align: "center",
        width: 620,
        height: 34,
        padding: [0, 10],
        background: card,
        radius: 10,
      }}
    >
      <Box style={{ flexDirection: "row", gap: 4 }}>
        {["1", "2", "3", "4"].map((name) => (
          <Box
            style={{
              padding: [2, 9],
              radius: 6,
              background: name === "2" ? accent : "#ffffff00",
            }}
          >
            <Text
              style={{
                fontSize: 12,
                fontWeight: "bold",
                color: name === "2" ? "#11111b" : name === "4" ? muted : foreground,
              }}
            >
              {name}
            </Text>
          </Box>
        ))}
      </Box>
      <Box style={{ flexDirection: "row", align: "center", gap: 10 }}>
        <Image symbol="wifi" size={14} color={foreground} />
        <Image symbol="battery.75percent" size={18} color={foreground} />
        <Text style={{ fontSize: 13, fontWeight: "medium", color: foreground }}>
          {clock.format("EEE d MMM  HH:mm")}
        </Text>
      </Box>
    </Box>
  );
}

function Launcher() {
  return (
    <Box style={{ width: 520, padding: [6, 8, 10, 8], background: card, radius: 18 }}>
      <Box style={{ flexDirection: "row", align: "center", gap: 12, padding: [12, 10] }}>
        <Image symbol="magnifyingglass" size={18} color={muted} />
        <Text style={{ fontSize: 20, color: muted }}>Search apps…</Text>
      </Box>
      <Box style={{ height: 1, background: "#ffffff12" }} />
      <Box style={{ padding: [10, 10, 6, 10] }}>
        <Text style={{ fontSize: 10, fontWeight: "bold", color: muted }}>
          PINNED & RECENT
        </Text>
      </Box>
      {apps.map(([bundle, name, folder], index) => (
        <Box
          style={{
            flexDirection: "row",
            align: "center",
            gap: 12,
            height: 46,
            padding: [0, 10],
            radius: 12,
            background: index === 0 ? "#89b4fa29" : "#ffffff00",
          }}
        >
          <Image app={bundle} size={30} />
          <Box style={{ grow: 1, gap: 1 }}>
            <Text style={{ fontSize: 14, fontWeight: "medium", color: foreground }}>
              {name}
            </Text>
            <Text style={{ fontSize: 11, color: muted }}>{folder}</Text>
          </Box>
        </Box>
      ))}
    </Box>
  );
}

function Clock() {
  return (
    <Box style={{ width: 240, padding: [14, 18], gap: 2, background: card, radius: 16 }}>
      <Text style={{ fontSize: 40, fontWeight: "semibold", color: foreground }}>
        {clock.format("HH:mm")}
      </Text>
      <Text style={{ fontSize: 13, color: muted }}>{clock.format("EEEE, d MMMM")}</Text>
    </Box>
  );
}

function Load() {
  const samples = [
    0.6, 0.8, 0.7, 1.1, 1.4, 1.2, 0.9, 1.3, 1.8, 1.6, 1.2, 1, 1.4, 1.7, 2, 1.8,
  ];
  return (
    <Box style={{ width: 240, padding: [12, 14], gap: 10, background: card, radius: 16 }}>
      <Box style={{ flexDirection: "row", justify: "space-between", align: "center" }}>
        <Text style={{ fontSize: 11, fontWeight: "semibold", color: muted }}>LOAD</Text>
        <Text style={{ fontSize: 20, fontWeight: "semibold", color: "#a6e3a1" }}>
          1.84
        </Text>
      </Box>
      <Box style={{ flexDirection: "row", align: "end", gap: 3, height: 36 }}>
        {samples.map((sample) => (
          <Box
            style={{
              width: 10,
              height: (sample / 2) * 36,
              background: "#a6e3a1",
              radius: 2,
            }}
          />
        ))}
      </Box>
    </Box>
  );
}

function Status() {
  const percent = (value: number | undefined) =>
    value === undefined ? "–" : `${Math.round(value * 100)}%`;
  const chip = (icon: string, text: () => string) => (
    <Box style={{ flexDirection: "row", align: "center", gap: 5 }}>
      <Image symbol={icon} size={13} color={foreground} />
      <Text style={{ fontSize: 12, fontWeight: "medium", color: foreground }}>
        {text}
      </Text>
    </Box>
  );
  return (
    <Box
      style={{
        flexDirection: "row",
        align: "center",
        gap: 14,
        padding: [6, 12],
        background: card,
        radius: 10,
      }}
    >
      <Box style={{ flexDirection: "row", align: "center", gap: 6 }}>
        <Image app={() => frontApp.bundleId() ?? ""} size={16} />
        <Text style={{ fontSize: 12, fontWeight: "semibold", color: foreground }}>
          {() => frontApp.name() ?? ""}
        </Text>
      </Box>
      {chip("cpu", () => percent(system.cpu()))}
      {chip("memorychip", () => percent(system.memory()))}
      {chip("wifi", () => network.type() ?? "–")}
      {chip("speaker.wave.2.fill", () => percent(audio.volume()))}
      {chip("battery.100", () => `${battery.percent() ?? "–"}%`)}
    </Box>
  );
}

function Shot(props: {
  name: string;
  screen: ScreenInfo;
  top: number;
  left: number;
  children: unknown;
}) {
  return (
    <Surface
      name={props.name}
      screen={props.screen}
      anchor={["top", "left"]}
      margins={[props.top, 0, 0, props.left]}
      layer="overlay"
    >
      {props.children as never}
    </Surface>
  );
}

export default function SiteShots({ screen }: WidgetProps) {
  return (
    <>
      <Shot name="bar" screen={screen} top={60} left={60}>
        <Bar />
      </Shot>
      <Shot name="launcher" screen={screen} top={140} left={60}>
        <Launcher />
      </Shot>
      <Shot name="cards" screen={screen} top={140} left={640}>
        <Box style={{ gap: 12 }}>
          <Clock />
          <Load />
        </Box>
      </Shot>
      <Shot name="status" screen={screen} top={60} left={760}>
        <Status />
      </Shot>
      <Shot name="hero" screen={screen} top={600} left={60}>
        <Box style={{ gap: 14, padding: 4 }}>
          <Bar />
          <Box style={{ flexDirection: "row", gap: 14, align: "start" }}>
            <Launcher />
            <Box style={{ gap: 12 }}>
              <Clock />
              <Load />
            </Box>
          </Box>
        </Box>
      </Shot>
    </>
  );
}
