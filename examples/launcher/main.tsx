// An app launcher plus a popup, exercising mouse, keyboard focus and named surfaces.
//
//   halo toggle launcher        # bind this to a hotkey in your WM, e.g. AeroSpace:
//                               # alt-space = 'exec-and-forget halo toggle launcher'
//
// Launcher: type to filter, ↑/↓ or hover to select, Enter or click to open, Esc or click elsewhere to close.
// Corner button: click for a popup anchored to it; click anywhere else to close it.

import {
  Box,
  Image,
  Input,
  PerScreen,
  Surface,
  Text,
  exec,
  hide,
  sh,
  show,
  type NativeNode,
  type ScreenInfo,
} from "halo";
import { clock } from "halo/services";
import { computed, signal } from "halo/signals";

const card = "#1e1e2ef2";
const foreground = "#cdd6f4";
const muted = "#9399b2";
const accent = "#89b4fa";
const selectedRow = "#89b4fa33";

interface App {
  name: string;
  path: string;
}

const apps = signal<App[]>([]);
sh(
  "ls -d /Applications/*.app /Applications/*/*.app /System/Applications/*.app /System/Applications/Utilities/*.app ~/Applications/*.app 2>/dev/null",
).then((result) =>
  apps.set(
    result.stdout
      .split("\n")
      .filter(Boolean)
      .map((path) => ({
        path,
        name: path
          .split("/")
          .pop()!
          .replace(/\.app$/, ""),
      }))
      .sort((a, b) => a.name.localeCompare(b.name)),
  ),
);

function Launcher(props: { screen: ScreenInfo }) {
  const query = signal("");
  const selected = signal(0);
  const results = computed(() => {
    const q = query().toLowerCase();
    const matches = apps().filter((app) => app.name.toLowerCase().includes(q));
    matches.sort(
      (a, b) =>
        Number(!a.name.toLowerCase().startsWith(q)) -
        Number(!b.name.toLowerCase().startsWith(q)),
    );
    return matches.slice(0, 7);
  });

  const open = (app: App | undefined) => {
    if (!app) return;
    exec("open", [app.path]);
    hide("launcher");
  };
  const move = (delta: number) =>
    selected.update((index) =>
      Math.max(0, Math.min(results().length - 1, index + delta)),
    );

  return (
    <Surface
      name="launcher"
      defaultHidden
      screen={props.screen}
      size={{ width: 560, height: 400 }}
      layer="overlay"
      input="keyboard"
      onFocus={() => (query.set(""), selected.set(0))}
      onBlur={() => hide("launcher")}
      enter={{
        from: { opacity: 0, scale: 0.96, translateY: -8 },
        curve: { stiffness: 380, damping: 28 },
      }}
      exit={{ to: { opacity: 0, scale: 0.98 }, duration: 110, curve: "ease-in" }}
    >
      <Box
        style={{
          padding: 12,
          gap: 8,
          background: card,
          radius: 18,
          borderWidth: 1,
          borderColor: "#ffffff1a",
        }}
      >
        <Box style={{ flexDirection: "row", align: "center", gap: 10, padding: [6, 8] }}>
          <Image symbol="magnifyingglass" size={18} color={muted} />
          <Input
            autofocus
            value={query}
            placeholder="Search apps"
            style={{ grow: 1, fontSize: 20, color: foreground }}
            onInput={(value) => (query.set(value), selected.set(0))}
            onKeyDown={({ key }) => {
              if (key === "ArrowDown") return (move(1), true);
              if (key === "ArrowUp") return (move(-1), true);
              if (key === "Enter") return (open(results()[selected()]), true);
              if (key === "Escape") return (hide("launcher"), true);
            }}
          />
        </Box>
        <Box style={{ height: 1, background: "#ffffff14" }} />
        <Box style={{ gap: 2 }}>
          {() =>
            results().map((app, index) => (
              <Box
                style={{
                  flexDirection: "row",
                  align: "center",
                  gap: 10,
                  padding: [6, 10],
                  radius: 8,
                  background: () => (selected() === index ? selectedRow : "transparent"),
                  transition: { background: 90 },
                }}
                onHover={(hovered) => hovered && selected.set(index)}
                onClick={() => open(app)}
              >
                <Image app={app.path} size={28} />
                <Text style={{ fontSize: 14, color: foreground }}>{app.name}</Text>
              </Box>
            ))
          }
        </Box>
      </Box>
    </Surface>
  );
}

function CornerButton(props: { screen: ScreenInfo }) {
  const open = signal(false);
  const hovered = signal(false);
  let button: NativeNode | undefined;

  return (
    <>
      <Surface
        screen={props.screen}
        anchor={["bottom", "left"]}
        margins={[0, 0, 16, 16]}
        size={{ width: 44, height: 44 }}
        layer="aboveMenu"
        input="interactive"
      >
        <Box
          ref={(node) => (button = node)}
          style={{
            justify: "center",
            align: "center",
            radius: 12,
            background: () => (hovered() || open() ? accent : card),
          }}
          onHover={hovered.set}
          onClick={() => open.update((value) => !value)}
        >
          <Image
            symbol="calendar"
            size={18}
            color={() => (hovered() || open() ? "#1e1e2e" : foreground)}
          />
        </Box>
      </Surface>
      <Surface
        screen={props.screen}
        size={{ width: 220, height: 128 }}
        layer="overlay"
        input="interactive"
        visible={open}
        attach={() => ({ to: button, side: "above", align: "start", offset: 8 })}
        onClickOutside={() => open.set(false)}
      >
        <Box
          style={{
            padding: 14,
            gap: 4,
            background: card,
            radius: 14,
            borderWidth: 1,
            borderColor: "#ffffff1a",
          }}
        >
          <Text style={{ fontSize: 28, fontWeight: "semibold", color: foreground }}>
            {clock.format("HH:mm")}
          </Text>
          <Text style={{ fontSize: 13, color: muted }}>
            {clock.format("EEEE, d MMMM")}
          </Text>
          <Box style={{ flexDirection: "row", justify: "end", padding: [6, 0, 0, 0] }}>
            <Box
              style={{ padding: [4, 10], radius: 6, background: accent }}
              onClick={() => (open.set(false), show("launcher"))}
            >
              <Text style={{ fontSize: 12, fontWeight: "semibold", color: "#1e1e2e" }}>
                Open launcher
              </Text>
            </Box>
          </Box>
        </Box>
      </Surface>
    </>
  );
}

export default () => (
  <PerScreen>
    {(screen) => (
      <>
        <Launcher screen={screen} />
        <CornerButton screen={screen} />
      </>
    )}
  </PerScreen>
);
