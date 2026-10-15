# Reactivity

Components run once. What changes afterwards is driven by signals.

![A clock and a load graph, both driven by signals](../assets/cards.png)

```tsx
import { computed, signal } from "halo/signals";

const count = signal(0);
const even = computed(() => count() % 2 === 0);
setInterval(() => count.update((n) => n + 1), 1000);

<Text style={{ color: () => (even() ? "#89b4fa" : "#f9e2af") }}>
  {() => `${count()}`}
</Text>;
```

## Rules

- Read a signal by calling it: `count()`. Write with `count.set(1)` or `count.update((n) => n + 1)`.
- A function in a prop or style value is reactive; a plain value is set once.
- In `<Text>`, only function children update: `{() => `WS ${ws()}`}`, not `WS {ws()}`.
- A function child of a `<Box>` re-renders when what it reads changes: `{() => items().map(Row)}`.

## Effects and cleanup

```tsx
effect(() => console.log("now", count()));
onCleanup(() => console.log("widget removed"));
```

Effects, timers and `poll` started in a component stop when it goes away or the config reloads. `batch()` groups
writes into one update.

## Getting data

| Helper                   | Use                                                              |
| ------------------------ | ---------------------------------------------------------------- |
| `clock.format("HH:mm")`  | Time and date, ticking only as often as the pattern needs.       |
| `sh("cmd")`, `exec(…)`   | Run a command once; resolves with its output.                    |
| `poll("cmd", 5000)`      | A signal of a command's output, refreshed on an interval.        |
| `externalSignal("name")` | State pushed by `halo trigger` ([guide](external-signals.html)). |

Reference: [`halo/signals`](../reference/halo-signals.html), [`halo/services`](../reference/halo-services.html).
