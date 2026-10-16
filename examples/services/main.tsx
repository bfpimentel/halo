// Every built-in service: a status strip (front app, CPU, memory, network, volume, battery, plus Low Power Mode and
// throttling chips when they apply), the last wake from sleep, and a volume OSD that appears when the volume or
// mute changes. Scroll over the volume chip to change it.

import { Box, Image, PerScreen, Surface, Text, type ScreenInfo } from "halo";
import { audio, battery, frontApp, network, power, session, system } from "halo/services";
import { computed, effect, signal, untrack } from "halo/signals";

const card = "#1e1e2ef0";
const foreground = "#cdd6f4";
const muted = "#7f849c";
const accent = "#89b4fa";

const percent = (value: number | undefined) =>
  value === undefined ? "–" : `${Math.round(value * 100)}%`;

function Chip(props: {
  icon: () => string;
  text: () => string;
  onScroll?: (dy: number) => void;
}) {
  return (
    <Box
      style={{ flexDirection: "row", align: "center", gap: 5 }}
      onScroll={props.onScroll && ((event) => props.onScroll?.(event.dy))}
    >
      <Image symbol={props.icon} size={13} color={foreground} />
      <Text style={{ fontSize: 12, fontWeight: "medium", color: foreground }}>
        {props.text}
      </Text>
    </Box>
  );
}

function batteryIcon() {
  const level = battery.percent() ?? 0;
  if (battery.charging()) return "battery.100.bolt";
  return level > 87
    ? "battery.100"
    : level > 62
      ? "battery.75"
      : level > 37
        ? "battery.50"
        : "battery.25";
}

function Status(props: { screen: ScreenInfo }) {
  return (
    <Surface
      screen={props.screen}
      anchor={["top", "right"]}
      margins={[48, 12, 0, 0]}
      layer="aboveMenu"
      input="interactive"
    >
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
        <Chip icon={() => "cpu"} text={() => percent(system.cpu())} />
        <Chip icon={() => "memorychip"} text={() => percent(system.memory())} />
        <Chip
          icon={() =>
            network.connected()
              ? network.type() === "ethernet"
                ? "cable.connector"
                : "wifi"
              : "wifi.slash"
          }
          text={() => network.type() ?? "–"}
        />
        <Chip
          icon={() => (audio.muted() ? "speaker.slash.fill" : "speaker.wave.2.fill")}
          text={() => (audio.volume() === undefined ? "fixed" : percent(audio.volume()))}
          onScroll={(dy) => audio.setVolume((untrack(audio.volume) ?? 0) + dy * 0.01)}
        />
        {() =>
          battery.present() ? (
            <Chip icon={batteryIcon} text={() => `${battery.percent() ?? "–"}%`} />
          ) : null
        }
        {() =>
          power.lowPowerMode() ? (
            <Chip icon={() => "leaf.fill"} text={() => "low power"} />
          ) : null
        }
        {() => {
          const thermal = power.thermal();
          return thermal && thermal !== "nominal" ? (
            <Chip icon={() => "thermometer.high"} text={() => thermal} />
          ) : null;
        }}
        {() => {
          const woke = session.lastWake();
          if (woke === undefined) return null;
          const time = new Date(woke);
          const pad = (n: number) => String(n).padStart(2, "0");
          return (
            <Chip
              icon={() => "sun.horizon"}
              text={() => `woke ${pad(time.getHours())}:${pad(time.getMinutes())}`}
            />
          );
        }}
      </Box>
    </Surface>
  );
}

function VolumeOsd(props: { screen: ScreenInfo }) {
  const visible = signal(false);
  const level = computed(() => (audio.muted() ? 0 : (audio.volume() ?? 0)));
  let first = true;
  let timer = 0;
  effect(() => {
    level();
    if (first) {
      first = false;
      return;
    }
    visible.set(true);
    clearTimeout(timer);
    timer = setTimeout(() => visible.set(false), 1500);
  });

  return (
    <Surface
      screen={props.screen}
      anchor={["bottom"]}
      margins={[0, 0, 80, 0]}
      layer="overlay"
      visible={visible}
      enter={{
        from: { opacity: 0, translateY: 16, scale: 0.94 },
        curve: { stiffness: 380, damping: 26 },
      }}
      exit={{ to: { opacity: 0, translateY: 10 }, duration: 160, curve: "ease-in" }}
    >
      <Box
        style={{
          flexDirection: "row",
          align: "center",
          gap: 12,
          padding: [14, 18],
          background: card,
          radius: 16,
        }}
      >
        <Image
          symbol={() => (audio.muted() ? "speaker.slash.fill" : "speaker.wave.3.fill")}
          size={20}
          color={foreground}
        />
        <Box style={{ width: 180, height: 6, radius: 3, background: "#ffffff1f" }}>
          <Box
            style={{
              height: 6,
              radius: 3,
              background: () => (audio.muted() ? muted : accent),
              width: () => `${Math.round(level() * 100)}%`,
              transition: { layout: { duration: 120 }, background: 120 },
            }}
          />
        </Box>
        <Text
          style={{
            fontSize: 13,
            fontWeight: "semibold",
            color: foreground,
            width: 36,
            textAlign: "right",
          }}
        >
          {() => percent(level())}
        </Text>
      </Box>
    </Surface>
  );
}

export default () => (
  <PerScreen>
    {(screen) => (
      <>
        <Status screen={screen} />
        <VolumeOsd screen={screen} />
      </>
    )}
  </PerScreen>
);
