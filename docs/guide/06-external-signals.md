# External signals

Push state into widgets from anywhere:

<video src="../assets/trigger.mp4" autoplay loop muted playsinline aria-label="Workspace pills following halo trigger commands"></video>

```bash
halo trigger music title="Song" artist="Band"
```

```tsx
import { externalSignal } from "halo/signals";

const music = externalSignal("music", { initial: { title: "", artist: "" } });
<Text>{() => `${music()?.title} — ${music()?.artist}`}</Text>;
```

- Payloads are string maps (`key=value`).
- `parse` turns a payload into any value; returning `undefined` ignores it.
- `hydrate` runs a shell command on load, so the value is right before the first trigger. Its result arrives as
  `{ stdout, stderr, code }`.
- The last payload survives reloads.

## AeroSpace

Window-manager support is something you build, not a halo module: a trigger from the WM's hooks plus a `hydrate`
query. The focused workspace:

```tsx
const focused = externalSignal("aerospace.workspace", {
  hydrate: "aerospace list-workspaces --focused",
  parse: (payload) => payload.focused ?? payload.stdout?.trim(),
});
<Text>{() => `WS ${focused()}`}</Text>;
```

Add to `aerospace.toml`:

```toml
exec-on-workspace-change = ['/bin/bash', '-c',
  'halo trigger aerospace.workspace focused=$AEROSPACE_FOCUSED_WORKSPACE prev=$AEROSPACE_PREV_WORKSPACE']
on-focus-changed = ['exec-and-forget halo trigger aerospace.focus']
```

For every workspace per display, with focus and emptiness, copy
[`examples/aerospace/aerospace.ts`](https://github.com/bfpimentel/halo/blob/main/examples/aerospace/aerospace.ts) into
your config. It maps AeroSpace monitors to halo displays through `ScreenInfo.index`, and the same shape works for yabai
or any WM with a CLI and change hooks.

Reference: [`externalSignal`](../reference/halo-signals.html#externalSignal), [CLI](../cli.html).
