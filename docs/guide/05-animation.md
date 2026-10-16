# Animation

Changes are instant unless you ask. Core Animation does the work, off the main thread.

## Transitions

Animate style changes:

```tsx
<Box
  style={{
    scale: () => (hovered() ? 1.05 : 1),
    background: () => (active() ? "#89b4fa" : "#313244"),
    transition: { scale: { curve: "spring" }, background: 150, layout: 200 },
  }}
/>
```

<video src="../assets/transition.mp4" autoplay loop muted playsinline aria-label="A square springs into a rotated green circle while a bar's width animates"></video>

Keys: any animatable property, `all`, or `layout` (position and size). On a `<Shape>` also `fill`, `stroke`, `track`,
`strokeWidth`, `strokeStart`, `strokeEnd` and `path` (morphs between paths with the same commands). Values: milliseconds or
`{ duration, curve, delay }`.

## Curves

`"linear"`, `"ease-in"`, `"ease-out"` (default), `"ease-in-out"`, cubic-bezier `[x1, y1, x2, y2]`, `"spring"`, or
`{ stiffness, damping, mass }`. Springs ignore `duration`.

<video src="../assets/curves.mp4" autoplay loop muted playsinline aria-label="Five dots crossing with linear, ease-in, ease-out, ease-in-out and spring curves"></video>

## Enter and exit

```tsx
<Box
  enter={{ from: { opacity: 0, translateY: 8 }, duration: 200 }}
  exit={{ to: { opacity: 0, scale: 0.9 }, duration: 150 }}
/>
```

On elements, when they appear or are removed. On a `<Surface>`, every time it's shown or hidden; hiding waits for
the exit.

<video src="../assets/show-hide.mp4" autoplay loop muted playsinline aria-label="A volume OSD springing in and fading out"></video>

<video src="../assets/enter-exit.mp4" autoplay loop muted playsinline aria-label="Notifications entering and leaving one at a time"></video>

In a list, use `<For>` so only the items that come and go animate; a plain `{() => items().map(…)}` rebuilds, and
so re-enters, every row.

```tsx
<For each={notifications} key={(n) => n.id}>
  {(n) => <Row title={n().title} enter={…} exit={…} />}
</For>
```

## Keyframes

```tsx
const spin = animate(
  icon,
  { rotate: [0, 360] },
  { duration: 1000, repeat: Infinity, curve: "linear" },
);
spin.cancel();
```

Options: `duration`, `curve`, `delay`, `repeat`, `alternate`, `offsets`, `fill`.

<video src="../assets/keyframes.mp4" autoplay loop muted playsinline aria-label="A spinner, a pulsing dot and a bouncing ball, each one animate() call"></video>

## Per frame

For anything else, JS runs on the display's refresh:

```tsx
const shown = tween(() => total(), { duration: 400 }); // a number that follows `total` smoothly
onFrame((time, dt) => {
  /* return false to stop */
});
```

<video src="../assets/frame.mp4" autoplay loop muted playsinline aria-label="A number tweening between two values next to a wave of dots driven by onFrame"></video>

Reference: [`animate`](../reference/halo.html#animate), [`Transitions`](../reference/halo.html#Transitions).
