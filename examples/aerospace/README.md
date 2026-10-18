# AeroSpace

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

For every workspace per display, with focus and emptiness, copy `aerospace.ts` (below) into your config. It maps
AeroSpace monitors to halo displays through `ScreenInfo.index`. Use halo's absolute path in `aerospace.toml` if
AeroSpace's `PATH` doesn't include it.
