# Elements

Four elements, laid out with flexbox and styled with a `style` object.

![A launcher built from Box, Text, Image and Input](../assets/launcher.png)

```tsx
<Box
  style={{
    flexDirection: "row",
    align: "center",
    gap: 8,
    padding: [6, 10],
    background: "#1e1e2e",
    radius: 8,
  }}
>
  <Image symbol="battery.75percent" size={16} color="#cdd6f4" />
  <Text style={{ fontSize: 13, color: "#cdd6f4" }}>85%</Text>
</Box>
```

## Box

A container. Layout: `flexDirection`, `justify`, `align`, `padding`, `gap`, `width`, `height`, `grow`, `shrink`.
Paint: `background`, `borderColor`, `borderWidth`, `radius`, `opacity`. Transforms: `scale`, `rotate`, `translateX`,
`translateY`, `origin`. Colors are `#rgb`, `#rrggbb` or `#rrggbbaa`.

## Text

Box style plus `color`, `fontSize`, `fontWeight` (`"medium"`, `"bold"`, 100–900), `fontFamily`, `lines` (1 by
default, 0 = no limit) and `textAlign`. Long text is truncated with "…". Emoji, CJK, right-to-left scripts and symbols
fall back to system fonts on their own, in any `fontFamily`; for SF Symbols use `<Image symbol>`.

## Image

One of `symbol` (an SF Symbol), `app` (a bundle id or `.app` path, for its icon) or `file`. `size` in points; `color`
tints symbols.

## Input

A native text field. Needs `input="keyboard"` on its surface.

```tsx
<Input
  autofocus
  value={query}
  placeholder="Search…"
  onInput={query.set}
  onKeyDown={(event) => {
    if (event.key !== "Escape") return false;
    hide("launcher");
    return true;
  }}
/>
```

`onKeyDown` gets every editing key with modifiers; return `true` to stop the default.

## Events

`onClick`, `onHover`, `onScroll` on Box, Text and Image. An event goes to the deepest element under the pointer that
listens for it. The surface needs `input="interactive"` (or `hover` for hover and scroll).

## Refs

`ref={(node) => …}` hands out the element, for popups (`attach`), `focus()` and `animate()`.

Reference: [`halo`](../reference/halo.html).
