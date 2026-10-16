// One shot per documented feature. A name ending in "@<seconds>" is recorded as a looping video of that length
// (scripts/screenshots.sh); the rest are screenshots. Videos get an opaque panel, since video has no alpha.

import {
  Box,
  Image,
  Input,
  Shape,
  Surface,
  Text,
  animate,
  onFrame,
  ring,
  sparkline,
  tween,
  type NativeNode,
  type ScreenInfo,
} from "halo";
import { clock } from "halo/services";
import { computed, externalSignal, signal } from "halo/signals";

const card = "#1e1e2ef2";
const panel = "#181825";
const surface = "#313244";
const track = "#45475a";
const foreground = "#cdd6f4";
const muted = "#7f849c";
const accent = "#89b4fa";
const green = "#a6e3a1";
const pink = "#f38ba8";
const yellow = "#f9e2af";

function Shot(props: {
  name: string;
  screen: ScreenInfo;
  top: number;
  left: number;
  input?: "keyboard";
  children: unknown;
}) {
  const video = props.name.includes("@");
  return (
    <Surface
      name={props.name}
      screen={props.screen}
      anchor={["top", "left"]}
      margins={[props.top, 0, 0, props.left]}
      layer="overlay"
      input={props.input ?? "passthrough"}
    >
      {video ? (
        <Box style={{ padding: 20, background: panel }}>{props.children as never}</Box>
      ) : (
        (props.children as never)
      )}
    </Surface>
  );
}

const Card = (props: { children: unknown; width?: number; gap?: number }) => (
  <Box
    style={{
      padding: 16,
      gap: props.gap ?? 12,
      background: card,
      radius: 14,
      width: props.width,
    }}
  >
    {props.children as never}
  </Box>
);

const label = (text: string) => (
  <Text style={{ fontSize: 11, fontWeight: "semibold", color: muted }}>{text}</Text>
);

/** Repeats `fn` every `ms`, starting now. */
function every(ms: number, fn: (tick: number) => void) {
  let tick = 0;
  fn(tick);
  setInterval(() => fn(++tick), ms);
}

function Starter() {
  return (
    <Box
      style={{
        width: 120,
        height: 48,
        justify: "center",
        align: "center",
        background: "#1e1e2ee0",
        radius: 12,
      }}
    >
      <Text style={{ fontSize: 22, fontWeight: "semibold", color: foreground }}>
        {clock.format("HH:mm")}
      </Text>
    </Box>
  );
}

function Popup() {
  return (
    <Box style={{ gap: 6, align: "start" }}>
      <Box
        style={{
          flexDirection: "row",
          align: "center",
          gap: 6,
          padding: [6, 10],
          background: card,
          radius: 8,
        }}
      >
        <Image symbol="calendar" size={13} color={foreground} />
        <Text style={{ fontSize: 12, fontWeight: "medium", color: foreground }}>
          Thu 16 Oct
        </Text>
      </Box>
      <Card width={200} gap={6}>
        {label("TODAY")}
        <Text style={{ fontSize: 13, color: foreground }}>10:00 Standup</Text>
        <Text style={{ fontSize: 13, color: foreground }}>14:30 Design review</Text>
        <Text style={{ fontSize: 13, color: muted }}>Nothing after 16:00</Text>
      </Card>
    </Box>
  );
}

function Boxes() {
  const swatch = (style: Record<string, unknown>, text: string) => (
    <Box style={{ gap: 6, align: "center" }}>
      <Box style={{ width: 64, height: 64, ...style }} />
      <Text style={{ fontSize: 11, color: muted }}>{text}</Text>
    </Box>
  );
  return (
    <Card>
      <Box style={{ flexDirection: "row", gap: 14 }}>
        {swatch({ background: accent }, "background")}
        {swatch({ background: "#cba6f7", radius: 16 }, "radius")}
        {swatch({ borderColor: green, borderWidth: 3, radius: 10 }, "border")}
        {swatch({ background: pink, opacity: 0.5, radius: 32 }, "opacity")}
        {swatch({ background: yellow, rotate: 12, scale: 0.8, radius: 8 }, "transform")}
      </Box>
      <Box
        style={{
          flexDirection: "row",
          gap: 6,
          padding: 8,
          background: surface,
          radius: 8,
        }}
      >
        {[1, 2, 3].map(() => (
          <Box style={{ grow: 1, height: 18, background: "#45475a", radius: 4 }} />
        ))}
      </Box>
      <Text style={{ fontSize: 11, color: muted }}>
        flexDirection: "row", gap: 6, padding: 8, grow: 1
      </Text>
    </Card>
  );
}

function Overlays() {
  return (
    <Card>
      <Box style={{ flexDirection: "row", gap: 28, align: "center" }}>
        <Box style={{ width: 48, height: 48 }}>
          <Image app="com.apple.mail" size={48} />
          <Box
            style={{
              position: "absolute",
              top: -4,
              right: -6,
              padding: [1, 6],
              background: "#e64553",
              radius: 9,
            }}
          >
            <Text style={{ fontSize: 11, fontWeight: "bold", color: "#ffffff" }}>12</Text>
          </Box>
        </Box>
        <Box style={{ width: 56, height: 56 }}>
          <Shape
            path={ring()}
            style={{
              width: 56,
              height: 56,
              fill: "transparent",
              stroke: green,
              track,
              strokeWidth: 6,
              lineCap: "round",
              strokeEnd: 0.72,
            }}
          />
          <Box
            style={{
              position: "absolute",
              top: 0,
              right: 0,
              bottom: 0,
              left: 0,
              justify: "center",
              align: "center",
            }}
          >
            <Text style={{ fontSize: 13, fontWeight: "bold", color: foreground }}>
              72%
            </Text>
          </Box>
        </Box>
      </Box>
    </Card>
  );
}

function Texts() {
  return (
    <Card width={300} gap={8}>
      <Text style={{ fontSize: 22, fontWeight: "bold", color: foreground }}>Bold 22</Text>
      <Text style={{ fontSize: 15, fontWeight: "medium", color: accent }}>
        Medium 15, colored
      </Text>
      <Text style={{ fontSize: 13, fontFamily: "Menlo", color: green }}>
        Menlo 13: ws 3 🎧
      </Text>
      <Text style={{ fontSize: 13, color: foreground }}>
        One line by default, so long text is truncated at the end of its box
      </Text>
      <Text style={{ fontSize: 13, color: muted, lines: 2 }}>
        lines: 2 wraps at the box width and truncates whatever doesn't fit on the second
        line
      </Text>
      <Text style={{ fontSize: 13, color: foreground, textAlign: "right" }}>
        textAlign: right
      </Text>
    </Card>
  );
}

function Images() {
  return (
    <Card>
      <Box style={{ flexDirection: "row", gap: 16, align: "center" }}>
        <Image symbol="wifi" size={24} color={foreground} />
        <Image symbol="battery.75percent" size={28} color={green} />
        <Image symbol="speaker.wave.2.fill" size={24} color={accent} />
        <Image symbol="moon.fill" size={22} color={yellow} />
        <Image app="com.apple.Safari" size={36} />
        <Image app="com.apple.Notes" size={36} />
        <Image app="/System/Applications/Calendar.app" size={36} />
      </Box>
      <Text style={{ fontSize: 11, color: muted }}>
        symbol + color · app (bundle id or .app path)
      </Text>
    </Card>
  );
}

function Shapes() {
  const values = [3, 5, 4, 8, 6, 9, 7, 11, 9, 12, 10, 14];
  return (
    <Card>
      <Box style={{ flexDirection: "row", gap: 20, align: "center" }}>
        <Shape
          path={ring()}
          style={{
            width: 52,
            height: 52,
            fill: "transparent",
            stroke: accent,
            track,
            strokeWidth: 6,
            lineCap: "round",
            strokeEnd: 0.6,
          }}
        />
        <Shape
          path={() => sparkline(values, { min: 0, area: true })}
          fit="stretch"
          style={{
            width: 140,
            height: 44,
            fill: "#a6e3a133",
            stroke: green,
            strokeWidth: 1.5,
            lineJoin: "round",
          }}
        />
        <Shape
          path="M 50 88 L 12 50 A 22 22 0 0 1 50 18 A 22 22 0 0 1 88 50 Z"
          style={{ width: 44, height: 44, fill: pink }}
        />
        <Shape
          path="M 10 50 L 40 80 L 90 20"
          style={{
            width: 40,
            height: 40,
            fill: "transparent",
            stroke: yellow,
            strokeWidth: 4,
            lineCap: "round",
            lineJoin: "round",
          }}
        />
      </Box>
      <Text style={{ fontSize: 11, color: muted }}>
        ring() · sparkline() · any SVG path
      </Text>
    </Card>
  );
}

function Inputs() {
  const query = signal("halo");
  return (
    <Card width={280} gap={10}>
      <Box style={{ padding: [8, 10], background: surface, radius: 8 }}>
        <Input
          placeholder="Search…"
          style={{ fontSize: 14, color: foreground, height: 18 }}
        />
      </Box>
      <Box style={{ padding: [8, 10], background: surface, radius: 8 }}>
        <Input
          value={query}
          onInput={query.set}
          style={{ fontSize: 14, color: foreground, height: 18 }}
        />
      </Box>
    </Card>
  );
}

function Events() {
  const hovered = signal(0);
  const pressed = signal(-1);
  every(700, (tick) => {
    hovered.set(tick % 3);
    pressed.set(tick % 3 === 2 ? 2 : -1);
  });
  return (
    <Card width={240} gap={4}>
      {["Open", "Rename", "Delete"].map((name, index) => (
        <Box
          style={{
            padding: [8, 10],
            radius: 8,
            background: () => (hovered() === index ? surface : "#31324400"),
            scale: () => (pressed() === index ? 0.96 : 1),
            transition: { background: 120, scale: { curve: "spring" } },
          }}
        >
          <Text style={{ fontSize: 13, color: index === 2 ? pink : foreground }}>
            {name}
          </Text>
        </Box>
      ))}
    </Card>
  );
}

function ShowHide() {
  const open = signal(true);
  every(1400, (tick) => open.set(tick % 2 === 0));
  return (
    <Box style={{ width: 240, height: 70, justify: "center", align: "center" }}>
      {() =>
        open() ? (
          <Box
            enter={{ from: { opacity: 0, scale: 0.9, translateY: 10 }, curve: "spring" }}
            exit={{ to: { opacity: 0, translateY: 6 }, duration: 160, curve: "ease-in" }}
            style={{
              flexDirection: "row",
              align: "center",
              gap: 10,
              padding: [12, 16],
              background: card,
              radius: 14,
            }}
          >
            <Image symbol="speaker.wave.2.fill" size={18} color={foreground} />
            <Box style={{ width: 120, height: 6, radius: 3, background: surface }}>
              <Box style={{ width: "60%", height: 6, radius: 3, background: accent }} />
            </Box>
          </Box>
        ) : null
      }
    </Box>
  );
}

function Signals() {
  const count = signal(0);
  const items = signal<string[]>([]);
  const names = ["Mail", "Notes", "Music", "Maps"];
  every(500, (tick) => {
    count.set(tick);
    items.set(names.slice(0, (Math.floor(tick / 2) % names.length) + 1));
  });
  return (
    <Box style={{ flexDirection: "row", gap: 16, width: 300, height: 150 }}>
      <Card width={110} gap={4}>
        {label("COUNT")}
        <Text style={{ fontSize: 30, fontWeight: "bold", color: foreground }}>
          {() => String(count())}
        </Text>
        <Text style={{ fontSize: 12, color: () => (count() % 2 ? green : muted) }}>
          {() => (count() % 2 ? "odd" : "even")}
        </Text>
      </Card>
      <Card width={150} gap={6}>
        {label("LIST")}
        {() =>
          items().map((name) => (
            <Text style={{ fontSize: 13, color: foreground }}>{name}</Text>
          ))
        }
      </Card>
    </Box>
  );
}

function Transitions() {
  const on = signal(false);
  every(1200, (tick) => on.set(tick % 2 === 1));
  return (
    <Box style={{ gap: 14, width: 300 }}>
      <Box style={{ flexDirection: "row", gap: 14, align: "center" }}>
        <Box
          style={{
            width: 56,
            height: 56,
            radius: () => (on() ? 28 : 10),
            background: () => (on() ? green : accent),
            scale: () => (on() ? 1.15 : 1),
            rotate: () => (on() ? 90 : 0),
            transition: { all: { curve: "spring" }, background: 250 },
          }}
        />
        <Text style={{ fontSize: 12, color: muted }}>
          scale · rotate · radius · background
        </Text>
      </Box>
      <Box style={{ height: 12, background: surface, radius: 6 }}>
        <Box
          style={{
            height: 12,
            radius: 6,
            background: yellow,
            width: () => (on() ? "90%" : "25%"),
            transition: { layout: { duration: 500, curve: "ease-in-out" } },
          }}
        />
      </Box>
      <Text style={{ fontSize: 12, color: muted }}>layout: width</Text>
    </Box>
  );
}

function Curves() {
  const on = signal(false);
  every(1300, (tick) => on.set(tick % 2 === 1));
  const curves = [
    ["linear", "linear"],
    ["ease-in", "ease-in"],
    ["ease-out", "ease-out"],
    ["ease-in-out", "ease-in-out"],
    ["spring", "spring"],
  ] as const;
  return (
    <Box style={{ gap: 10, width: 300 }}>
      {curves.map(([name, curve]) => (
        <Box style={{ flexDirection: "row", align: "center", gap: 10 }}>
          <Box style={{ width: 70 }}>
            <Text style={{ fontSize: 11, color: muted }}>{name}</Text>
          </Box>
          <Box style={{ grow: 1, height: 14 }}>
            <Box
              style={{
                width: 14,
                height: 14,
                radius: 7,
                background: accent,
                translateX: () => (on() ? 196 : 0),
                transition: { translateX: { duration: 800, curve } },
              }}
            />
          </Box>
        </Box>
      ))}
    </Box>
  );
}

function EnterExit() {
  // One reactive slot per row, each reading its own computed, so only the row that changes animates (a single
  // `items().map(...)` slot would rebuild, and so exit and re-enter, every row).
  const count = signal(0);
  every(700, (tick) => {
    const step = tick % 10;
    count.set(step <= 4 ? step : 9 - step);
  });
  return (
    <Box style={{ gap: 6, width: 240, height: 168 }}>
      {[1, 2, 3, 4].map((n) => {
        const shown = computed(() => count() >= n);
        return () =>
          shown() ? (
            <Box
              enter={{ from: { opacity: 0, translateX: -20 }, curve: "spring" }}
              exit={{ to: { opacity: 0, scale: 0.9 }, duration: 180 }}
              style={{ padding: [8, 12], background: card, radius: 8 }}
            >
              <Text
                style={{ fontSize: 13, color: foreground }}
              >{`Notification ${n}`}</Text>
            </Box>
          ) : null;
      })}
    </Box>
  );
}

function Keyframes() {
  let spinner: NativeNode | undefined;
  let dot: NativeNode | undefined;
  setTimeout(() => {
    if (spinner)
      animate(
        spinner,
        { rotate: [0, 360] },
        { duration: 1000, repeat: Infinity, curve: "linear" },
      );
    if (dot)
      animate(
        dot,
        { scale: [1, 1.6, 1], opacity: [1, 0.4, 1] },
        { duration: 900, repeat: Infinity, curve: "ease-in-out" },
      );
  }, 50);
  return (
    <Box
      style={{
        flexDirection: "row",
        gap: 40,
        align: "center",
        width: 240,
        padding: [6, 20],
      }}
    >
      <Box ref={(node) => (spinner = node)} style={{ width: 40, height: 40 }}>
        <Shape
          path={ring()}
          style={{
            width: 40,
            height: 40,
            fill: "transparent",
            stroke: accent,
            strokeWidth: 4,
            lineCap: "round",
            strokeEnd: 0.7,
          }}
        />
      </Box>
      <Box
        ref={(node) => (dot = node)}
        style={{ width: 18, height: 18, radius: 9, background: green }}
      />
      <Box style={{ width: 20, height: 40, justify: "end" }}>
        <Box
          ref={(node) =>
            animate(
              node,
              { translateY: [0, -22, 0] },
              { duration: 700, repeat: Infinity, curve: "ease-out" },
            )
          }
          style={{ width: 20, height: 20, radius: 10, background: yellow }}
        />
      </Box>
    </Box>
  );
}

function PerFrame() {
  const target = signal(0);
  every(1500, (tick) => target.set(tick % 2 ? 1280 : 340));
  const shown = tween(() => target(), { duration: 900, curve: "ease-in-out" });
  const phase = signal(0);
  onFrame((time) => phase.set(time / 400));
  return (
    <Box style={{ flexDirection: "row", gap: 24, align: "center", width: 300 }}>
      <Box style={{ gap: 2 }}>
        {label("TWEEN")}
        <Text style={{ fontSize: 28, fontWeight: "bold", color: foreground, width: 130 }}>
          {() => `${Math.round(shown())} MB`}
        </Text>
      </Box>
      <Box style={{ flexDirection: "row", gap: 6, align: "center", height: 50 }}>
        {[0, 1, 2, 3, 4, 5].map((i) => (
          <Box
            style={{
              width: 8,
              height: 8,
              radius: 4,
              background: accent,
              translateY: () => Math.sin(phase() + i * 0.7) * 16,
            }}
          />
        ))}
      </Box>
    </Box>
  );
}

function Trigger() {
  const focused = externalSignal("docs.workspace", {
    initial: "1",
    parse: (payload) => payload.focused,
  });
  return (
    <Box style={{ gap: 10, width: 260 }}>
      <Box
        style={{ flexDirection: "row", gap: 4, padding: 6, background: card, radius: 10 }}
      >
        {["1", "2", "3", "4", "5"].map((name) => (
          <Box
            style={{
              padding: [3, 11],
              radius: 6,
              background: () => (focused() === name ? accent : "#89b4fa00"),
              transition: { background: 150 },
            }}
          >
            <Text
              style={{
                fontSize: 13,
                fontWeight: "bold",
                color: () => (focused() === name ? "#11111b" : foreground),
              }}
            >
              {name}
            </Text>
          </Box>
        ))}
      </Box>
      <Text style={{ fontSize: 11, fontFamily: "Menlo", color: muted }}>
        {() => `$ halo trigger docs.workspace focused=${focused()}`}
      </Text>
    </Box>
  );
}

export function DocShots(props: { screen: ScreenInfo }) {
  const screen = props.screen;
  return (
    <>
      <Shot name="starter" screen={screen} top={60} left={1000}>
        <Starter />
      </Shot>
      <Shot name="popup" screen={screen} top={140} left={1000}>
        <Popup />
      </Shot>
      <Shot name="box" screen={screen} top={60} left={1300}>
        <Boxes />
      </Shot>
      <Shot name="overlay" screen={screen} top={300} left={1300}>
        <Overlays />
      </Shot>
      <Shot name="text" screen={screen} top={60} left={1800}>
        <Texts />
      </Shot>
      <Shot name="image" screen={screen} top={360} left={1800}>
        <Images />
      </Shot>
      <Shot name="shape" screen={screen} top={460} left={1300}>
        <Shapes />
      </Shot>
      <Shot name="input" screen={screen} top={480} left={1800} input="keyboard">
        <Inputs />
      </Shot>
      <Shot name="events@4" screen={screen} top={1000} left={60}>
        <Events />
      </Shot>
      <Shot name="show-hide@5" screen={screen} top={1000} left={360}>
        <ShowHide />
      </Shot>
      <Shot name="signals@5" screen={screen} top={1000} left={660}>
        <Signals />
      </Shot>
      <Shot name="transition@5" screen={screen} top={700} left={1000}>
        <Transitions />
      </Shot>
      <Shot name="curves@5" screen={screen} top={700} left={1400}>
        <Curves />
      </Shot>
      <Shot name="enter-exit@6" screen={screen} top={700} left={1800}>
        <EnterExit />
      </Shot>
      <Shot name="keyframes@4" screen={screen} top={1000} left={1050}>
        <Keyframes />
      </Shot>
      <Shot name="frame@5" screen={screen} top={1000} left={1400}>
        <PerFrame />
      </Shot>
      <Shot name="trigger@6" screen={screen} top={1000} left={1800}>
        <Trigger />
      </Shot>
    </>
  );
}
