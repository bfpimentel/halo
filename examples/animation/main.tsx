// Every animation layer, driven by timers so it plays without input:
// transitions (style changes), keyframes (spinner, pulse), enter/exit (list items, toast surface),
// layout transitions (the list reflowing) and a JS tween (the counter).

import {
  Box,
  For,
  Image,
  PerScreen,
  Surface,
  Text,
  animate,
  tween,
  type NativeNode,
  type ScreenInfo,
} from "halo";
import { signal } from "halo/signals";

const card = "#1e1e2ef0";
const foreground = "#cdd6f4";
const muted = "#9399b2";
const palette = ["#89b4fa", "#a6e3a1", "#f9e2af", "#f38ba8", "#cba6f7", "#94e2d5"];

const tick = signal(0);
setInterval(() => tick.update((n) => n + 1), 1200);

function Showcase() {
  const items = signal([0, 1, 2]);
  let next = 3;
  setInterval(() => {
    items.update((list) =>
      list.length >= 5 || (list.length > 2 && Math.random() < 0.5)
        ? list.slice(1)
        : [...list, next++],
    );
  }, 900);

  const total = tween(() => tick() * 137, { duration: 700, curve: "ease-out" });

  let spinner: NativeNode | undefined;
  let dot: NativeNode | undefined;

  const showcase = (
    <Box
      style={{
        padding: 18,
        gap: 16,
        background: card,
        radius: 18,
        borderWidth: 1,
        borderColor: "#ffffff1a",
      }}
    >
      <Box style={{ flexDirection: "row", justify: "space-between", align: "center" }}>
        <Text style={{ fontSize: 12, fontWeight: "semibold", color: muted }}>
          ANIMATION
        </Text>
        <Box style={{ flexDirection: "row", gap: 10, align: "center" }}>
          <Box
            ref={(node) => (dot = node)}
            style={{ width: 8, height: 8, radius: 4, background: "#a6e3a1" }}
          />
          <Image
            ref={(node) => (spinner = node)}
            symbol="arrow.triangle.2.circlepath"
            size={16}
            color={muted}
          />
        </Box>
      </Box>

      <Box style={{ flexDirection: "row", align: "center", gap: 14 }}>
        <Box
          style={{
            width: 56,
            height: 56,
            radius: () => (tick() % 2 ? 28 : 12),
            background: () => palette[tick() % palette.length],
            scale: () => (tick() % 2 ? 1.12 : 0.9),
            rotate: () => (tick() % 2 ? 45 : 0),
            transition: {
              all: { curve: { stiffness: 220, damping: 12 } },
              background: 400,
            },
          }}
        />
        <Box style={{ gap: 2 }}>
          <Text style={{ fontSize: 28, fontWeight: "bold", color: foreground }}>
            {() => Math.round(total()).toLocaleString("en-US")}
          </Text>
          <Text style={{ fontSize: 12, color: muted }}>tweened counter</Text>
        </Box>
      </Box>

      <Box style={{ flexDirection: "row", gap: 8, height: 32 }}>
        <For each={items}>
          {(item) => (
            <Box
              style={{
                width: 52,
                height: 32,
                radius: 8,
                background: palette[item() % palette.length],
                justify: "center",
                align: "center",
                transition: { layout: { duration: 300, curve: "ease-in-out" } },
              }}
              enter={{ from: { opacity: 0, scale: 0.6 }, curve: "spring" }}
              exit={{ to: { opacity: 0, translateY: -14 }, duration: 220 }}
            >
              <Text style={{ fontSize: 12, fontWeight: "semibold", color: "#1e1e2e" }}>
                {String(item())}
              </Text>
            </Box>
          )}
        </For>
      </Box>
    </Box>
  );

  if (spinner)
    animate(
      spinner,
      { rotate: [0, 360] },
      { duration: 1400, repeat: Infinity, curve: "linear" },
    );
  if (dot)
    animate(
      dot,
      { opacity: [1, 0.25], scale: [1, 1.6] },
      { duration: 700, repeat: Infinity, alternate: true, curve: "ease-in-out" },
    );
  return showcase;
}

function Toast(props: { screen: ScreenInfo }) {
  return (
    <Surface
      screen={props.screen}
      anchor={["bottom"]}
      margins={[0, 0, 40, 0]}
      size={{ width: 300, height: 52 }}
      layer="overlay"
      visible={() => tick() % 4 < 2}
      enter={{
        from: { opacity: 0, translateY: 30, scale: 0.9 },
        curve: { stiffness: 260, damping: 18 },
      }}
      exit={{ to: { opacity: 0, translateY: 20 }, duration: 200, curve: "ease-in" }}
    >
      <Box
        style={{
          flexDirection: "row",
          align: "center",
          gap: 10,
          padding: [0, 16],
          background: card,
          radius: 14,
        }}
      >
        <Image symbol="bell.fill" size={16} color="#f9e2af" />
        <Text style={{ fontSize: 13, color: foreground }}>Surface enter / exit</Text>
      </Box>
    </Surface>
  );
}

export default () => (
  <PerScreen>
    {(screen) => (
      <>
        <Surface screen={screen} size={{ width: 380, height: 220 }} layer="aboveMenu">
          <Showcase />
        </Surface>
        <Toast screen={screen} />
      </>
    )}
  </PerScreen>
);
