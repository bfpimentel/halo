import type { EnterTransition, ExitTransition, Transitions } from "halo/animation";
import { listen, type ClickEvent, type KeyEvent, type ScrollEvent } from "halo/events";
import { reportError } from "halo/host";
import { native, type ScreenInfo } from "halo/native";
import {
  batch,
  computed,
  effect,
  getOwner,
  onCleanup,
  root,
  runWithOwner,
  signal,
  untrack,
  type Accessor,
  type Signal,
} from "halo/reactive";

/** A value, or a function returning it that is re-read when the signals it reads change. */
export type Reactive<T> = T | Accessor<T>;

/** A handle to a rendered element, from `ref`. Pass it to `attach`, `focus()` or `animate()`. */
export class NativeNode {
  constructor(readonly id: number) {}
}

/** Anything a component or child slot can return. */
export type Element =
  | NativeNode
  | string
  | number
  | boolean
  | null
  | undefined
  | Accessor<unknown>
  | Element[];

type Color = string;
type Length = number | `${number}%` | "auto";
type Spacing =
  | number
  | [vertical: number, horizontal: number]
  | [top: number, right: number, bottom: number, left: number];

/** Layout and paint properties. Every value can be reactive. */
export interface BoxStyle {
  flexDirection?: "row" | "column";
  justify?:
    | "start"
    | "center"
    | "end"
    | "space-between"
    | "space-around"
    | "space-evenly";
  align?: "start" | "center" | "end" | "stretch";
  padding?: Spacing;
  gap?: number;
  width?: Length;
  height?: Length;
  grow?: number;
  shrink?: number;
  /** `"absolute"` takes the node out of the row/column and places it over its siblings with `top`/`right`/`bottom`/`left`. */
  position?: "relative" | "absolute";
  /** Offset from the parent's top edge (absolute) or from the node's own place (relative). Points or `"50%"`. */
  top?: Length;
  right?: Length;
  bottom?: Length;
  left?: Length;
  background?: Color;
  borderColor?: Color;
  borderWidth?: number;
  radius?: number;
  opacity?: number;
  scale?: number;
  /** Degrees, clockwise. */
  rotate?: number;
  translateX?: number;
  translateY?: number;
  /** Pivot for scale/rotate as fractions of the node's size; defaults to the center, [0.5, 0.5]. */
  origin?: [x: number, y: number];
  /** Animate changes instead of jumping: `{ opacity: 150, scale: { duration: 300, curve: "spring" }, layout: 200 }`. */
  transition?: Transitions;
}

/** Box properties plus text properties. */
export interface TextStyle extends BoxStyle {
  /** Lines before truncating; 1 by default, 0 for no limit. More than one wraps at the box's width. */
  lines?: number;
  textAlign?: "left" | "center" | "right";
  color?: Color;
  fontSize?: number;
  fontWeight?: "regular" | "medium" | "semibold" | "bold" | number;
  fontFamily?: string;
}

/** Box properties plus shape paint. Shape paint animates with `transition` like any other property. */
export interface ShapeStyle extends BoxStyle {
  /** Fill color; white by default, `"transparent"` for none. */
  fill?: Color;
  /** Stroke color; none by default. */
  stroke?: Color;
  /** Color of the whole path under the stroke: the empty part of a progress ring or bar. */
  track?: Color;
  /** In points, whatever the shape's scale. Default 1. */
  strokeWidth?: number;
  /** Where the stroke starts and ends along the path, 0–1. Animate `strokeEnd` for progress rings. */
  strokeStart?: number;
  strokeEnd?: number;
  lineCap?: "butt" | "round" | "square";
  lineJoin?: "miter" | "round" | "bevel";
}

/** A style object (or a function returning one); each property can also be reactive on its own. */
export type StyleProp<S> = Reactive<{ [K in keyof S]?: Reactive<S[K]> }>;

function read<T>(value: Reactive<T>): T {
  return typeof value === "function" ? (value as Accessor<T>)() : value;
}

/** Event props shared by Box, Text and Image. Events bubble to the closest ancestor listening for them. */
export interface Interactive {
  /** Played once, when the node first appears: `{ from: { opacity: 0, translateY: 8 }, duration: 200 }`. */
  enter?: EnterTransition;
  /** Played when the node is removed (e.g. a list item going away); it leaves the layout right away. */
  exit?: ExitTransition;
  onClick?: (event: ClickEvent) => void;
  onScroll?: (event: ScrollEvent) => void;
  onHover?: (hovered: boolean) => void;
  ref?: (node: NativeNode) => void;
}

function wire(node: NativeNode, props: Interactive): void {
  if (props.enter) native.setProp(node.id, "enter", props.enter);
  if (props.exit) native.setProp(node.id, "exit", props.exit);
  listen(node.id, "click", props.onClick);
  listen(node.id, "scroll", props.onScroll);
  listen(node.id, "hover", props.onHover);
  props.ref?.(node);
}

function createNode(kind: "box" | "text" | "image" | "input" | "shape"): NativeNode {
  const id = native.createNode(kind);
  onCleanup(() => native.destroyNode(id));
  return new NativeNode(id);
}

function applyStyle<S extends object>(
  node: NativeNode,
  style: StyleProp<S> | undefined,
): void {
  if (!style) return;
  if (typeof style === "function") {
    let previous: string[] = [];
    effect(() => {
      const current = style();
      for (const key of previous)
        if (!(key in current)) native.setStyle(node.id, key, null);
      for (const [key, value] of Object.entries(current))
        native.setStyle(node.id, key, read(value));
      previous = Object.keys(current);
    });
    return;
  }
  for (const [key, value] of Object.entries(style)) {
    if (typeof value === "function") effect(() => native.setStyle(node.id, key, value()));
    else native.setStyle(node.id, key, value);
  }
}

function flatten(children: Element, out: Element[] = []): Element[] {
  if (Array.isArray(children)) for (const child of children) flatten(child, out);
  else if (
    children !== null &&
    children !== undefined &&
    children !== false &&
    children !== true
  )
    out.push(children);
  return out;
}

function toNodes(value: Element): NativeNode[] {
  return flatten(value).flatMap((item) => {
    if (item instanceof NativeNode) return [item];
    if (typeof item === "function") return toNodes(item() as Element);
    return [Text({ children: String(item) })];
  });
}

/**
 * Static children are inserted once; each function child is a slot re-rendered when what it reads changes.
 * A slot only moves the nodes whose place changed, so nodes it gets back again (from `<For>`) stay put.
 */
function appendChildren(parent: NativeNode, children: Element): void {
  const sizes: number[] = [];
  for (const child of flatten(children)) {
    const slot = sizes.length;
    if (typeof child !== "function") {
      const nodes = toNodes(child);
      for (const node of nodes)
        native.insert(parent.id, node.id, Number.MAX_SAFE_INTEGER);
      sizes.push(nodes.length);
      continue;
    }
    sizes.push(0);
    let current: NativeNode[] = [];
    effect(() => {
      const nodes = toNodes(child() as Element);
      const kept = new Set(nodes);
      for (const node of current) if (!kept.has(node)) native.detach(node.id);
      const placed = current.filter((node) => kept.has(node));
      const start = sizes.slice(0, slot).reduce((sum, size) => sum + size, 0);
      nodes.forEach((node, index) => {
        if (placed[index] === node) return;
        const from = placed.indexOf(node);
        if (from >= 0) placed.splice(from, 1);
        placed.splice(index, 0, node);
        native.insert(parent.id, node.id, start + index);
      });
      sizes[slot] = nodes.length;
      current = nodes;
    });
  }
}

/** Props of `<For>`. */
export interface ForProps<T> {
  /** The list; usually a signal or computed. */
  each: Reactive<readonly T[]>;
  /** Identifies an item across updates (an id); defaults to the item itself. Keys must be unique. */
  key?: (item: T, index: number) => unknown;
  /** Called once per key. `item` and `index` update when that key's value or position changes. */
  children: (item: Accessor<T>, index: Accessor<number>) => Element;
}

interface Row<T> {
  item: Signal<T>;
  index: Signal<number>;
  nodes: NativeNode[];
  dispose: () => void;
}

/**
 * A keyed list: only new keys render, removed keys are disposed (playing their `exit`), and kept ones are
 * reused and moved. Use it inside a `<Box>`, instead of `{() => items().map(...)}`.
 */
export function For<T>(props: ForProps<T>): Accessor<NativeNode[]> {
  const owner = getOwner();
  let rows = new Map<unknown, Row<T>>();
  const render = (item: T, index: number) =>
    runWithOwner(owner, () =>
      root((dispose) => {
        const row: Row<T> = {
          item: signal(item),
          index: signal(index),
          nodes: [],
          dispose,
        };
        try {
          row.nodes = toNodes(props.children(row.item, row.index));
        } catch (error) {
          reportError(error);
        }
        return row;
      }),
    );
  return computed(
    () => {
      const list = read(props.each);
      return untrack(() =>
        batch(() => {
          const next = new Map<unknown, Row<T>>();
          list.forEach((item, index) => {
            const key = props.key ? props.key(item, index) : item;
            if (next.has(key))
              return reportError(new Error(`<For>: duplicate key ${String(key)}`));
            const row = rows.get(key);
            if (row) {
              row.item.set(item);
              row.index.set(index);
            }
            next.set(key, row ?? render(item, index));
          });
          for (const [key, row] of rows) if (!next.has(key)) row.dispose();
          rows = next;
          return [...next.values()].flatMap((row) => row.nodes);
        }),
      );
    },
    { equals: (a, b) => a.length === b.length && a.every((node, i) => node === b[i]) },
  );
}

/** Props of `<Box>`. */
export interface BoxProps extends Interactive {
  style?: StyleProp<BoxStyle>;
  /** Nodes, strings, or functions returning them (re-rendered when what they read changes). */
  children?: Element;
}

/** A flexbox container. Strings among its children become `<Text>`. */
export function Box(props: BoxProps): NativeNode {
  const node = createNode("box");
  applyStyle(node, props.style);
  appendChildren(node, props.children);
  wire(node, props);
  return node;
}

/** Props of `<Text>`. */
export interface TextProps extends Interactive {
  style?: StyleProp<TextStyle>;
  /** Strings and numbers; only function children update: `{() => `WS ${ws()}`}`. */
  children?: Element;
}

/** Text, one line by default (see `TextStyle.lines`). */
export function Text(props: TextProps): NativeNode {
  const node = createNode("text");
  wire(node, props);
  applyStyle(node, props.style);
  const parts = flatten(props.children);
  const render = () =>
    parts.map((part) => String(typeof part === "function" ? part() : part)).join("");
  if (parts.some((part) => typeof part === "function"))
    effect(() => native.setProp(node.id, "text", render()));
  else native.setProp(node.id, "text", render());
  return node;
}

/** Props of `<Image>`: set one of `symbol`, `app` or `file`. */
export interface ImageProps extends Interactive {
  /** An SF Symbol name, e.g. `"battery.75percent"`. */
  symbol?: Reactive<string>;
  /** A bundle id (`"com.apple.Safari"`) or an absolute `.app` path. */
  app?: Reactive<string>;
  /** An image file path; `~` is expanded. */
  file?: Reactive<string>;
  /** Width and height in points. Default 16. */
  size?: Reactive<number>;
  /** Tint for SF Symbols. */
  color?: Reactive<Color>;
  style?: StyleProp<BoxStyle>;
}

/** An SF Symbol, an app icon or an image file. */
export function Image(props: ImageProps): NativeNode {
  const node = createNode("image");
  for (const key of ["size", "color", "symbol", "app", "file"] as const) {
    const value = props[key];
    if (typeof value === "function") effect(() => native.setProp(node.id, key, value()));
    else if (value !== undefined) native.setProp(node.id, key, value);
  }
  applyStyle(node, props.style);
  wire(node, props);
  return node;
}

/** Props of `<Shape>`. Give it a size (`style.width`/`height`), like a Box with no content. */
export interface ShapeProps extends Interactive {
  /** SVG path data (`"M 0 0 L 100 100"`, arcs included), in `viewBox` coordinates. `ring()` and `sparkline()` make common ones. */
  path: Reactive<string>;
  /** The path's coordinate space. Default [100, 100]. */
  viewBox?: Reactive<[width: number, height: number]>;
  /** `"contain"` (default) keeps proportions, centered; `"stretch"` fills each axis (graphs). */
  fit?: Reactive<"contain" | "stretch">;
  style?: StyleProp<ShapeStyle>;
}

/** Vector paths: rings, graphs, icons. Strokes keep their width in points and stay inside the node. */
export function Shape(props: ShapeProps): NativeNode {
  const node = createNode("shape");
  for (const key of ["viewBox", "fit", "path"] as const) {
    const value = props[key];
    if (typeof value === "function") effect(() => native.setProp(node.id, key, value()));
    else if (value !== undefined) native.setProp(node.id, key, value);
  }
  applyStyle(node, props.style);
  wire(node, props);
  return node;
}

/** Props of `<Input>`. */
export interface InputProps {
  /** The text; pass the signal you update in `onInput`. */
  value?: Reactive<string>;
  placeholder?: Reactive<string>;
  /** Take focus whenever its surface does. */
  autofocus?: boolean;
  style?: StyleProp<TextStyle>;
  /** Every edit, with the new text. */
  onInput?: (value: string) => void;
  /** Enter, unless `onKeyDown` handled it. */
  onSubmit?: (value: string) => void;
  /** Every editing key (Enter, Escape, arrows, Tab, Home/End…) with modifiers; return true to stop the default. */
  onKeyDown?: (event: KeyEvent) => boolean | void;
  ref?: (node: NativeNode) => void;
}

/** A native single-line text field (IME, selection, clipboard). Needs an `input="keyboard"` surface. */
export function Input(props: InputProps): NativeNode {
  const node = createNode("input");
  for (const key of ["value", "placeholder"] as const) {
    const value = props[key];
    if (typeof value === "function") effect(() => native.setProp(node.id, key, value()));
    else if (value !== undefined) native.setProp(node.id, key, value);
  }
  if (props.autofocus) native.setProp(node.id, "autofocus", true);
  applyStyle(node, props.style);
  listen(node.id, "input", props.onInput);
  listen(node.id, "submit", props.onSubmit);
  listen(node.id, "key", props.onKeyDown);
  props.ref?.(node);
  return node;
}

/** Moves keyboard focus into an `<Input>` (its surface must have focus). */
export function focus(node: NativeNode): void {
  native.focus(node.id);
}

/** A screen edge to anchor a surface to. */
export type Edge = "top" | "bottom" | "left" | "right";

/** Where an attached surface (a popup) sits relative to a node. */
export interface Attachment {
  to: NativeNode | undefined;
  side?: "below" | "above" | "left" | "right";
  align?: "start" | "center" | "end";
  offset?: number;
}

/** How a surface is placed, stacked and made interactive. */
export interface SurfaceProps {
  /** Target for `halo show|hide|toggle <name>`; shared by this widget's instance on every display. */
  name?: string;
  /** Start hidden the first time this name appears (e.g. a launcher opened by a hotkey). */
  defaultHidden?: boolean;
  /** Place next to a node of another surface instead of anchoring to the screen. Follows the node as it moves. */
  attach?: Reactive<Attachment>;
  onKeyDown?: (event: KeyEvent) => boolean | void;
  onFocus?: () => void;
  onBlur?: () => void;
  /** A click anywhere outside this surface, in any app. */
  onClickOutside?: () => void;
  /** Played on the content every time the surface appears (including `halo show`). */
  enter?: EnterTransition;
  /** Played before the surface hides; it stays on screen until the animation ends. */
  exit?: ExitTransition;
  screen: Reactive<number | ScreenInfo>;
  anchor?: Reactive<Edge[]>;
  margins?: Reactive<Spacing>;
  /**
   * Per axis: points, "fill" (between both anchors), or "auto" (the content's size). Omitted axes are "fill" when
   * anchored to both edges of that axis and "auto" otherwise.
   */
  size?: Reactive<{
    width?: number | "fill" | "auto";
    height?: number | "fill" | "auto";
  }>;
  layer?: Reactive<"desktop" | "belowMenu" | "aboveMenu" | "overlay">;
  input?: Reactive<"passthrough" | "hover" | "interactive" | "keyboard">;
  avoid?: Reactive<("notch" | "menuBar")[]>;
  visible?: Reactive<boolean>;
  children?: Element;
}

/** A top-level window. Its child is laid out to fill it. */
export function Surface(props: SurfaceProps): null {
  const children = flatten(props.children);
  const content =
    children.length === 1 && children[0] instanceof NativeNode
      ? children[0]
      : Box({ children: props.children });

  let id = 0;
  effect(() => {
    const screen = read(props.screen);
    const config = {
      screen: typeof screen === "number" ? screen : screen.id,
      anchor: read(props.anchor),
      margins: read(props.margins),
      size: read(props.size),
      layer: read(props.layer),
      input: read(props.input),
      avoid: read(props.avoid),
      visible: read(props.visible),
      name: props.name,
      defaultHidden: props.defaultHidden,
      attach: attachment(props.attach),
      enter: props.enter,
      exit: props.exit,
    };
    if (id === 0) id = native.createSurface(content.id, config);
    else native.updateSurface(id, config);
  });
  listen(id, "key", props.onKeyDown);
  listen(id, "focus", props.onFocus);
  listen(id, "blur", props.onBlur);
  listen(id, "clickOutside", props.onClickOutside);
  onCleanup(() => native.destroySurface(id));
  return null;
}

function attachment(value: Reactive<Attachment> | undefined) {
  const attach = value === undefined ? undefined : read(value);
  if (!attach?.to) return undefined;
  return {
    node: attach.to.id,
    side: attach.side,
    align: attach.align,
    offset: attach.offset,
  };
}

const screenList = signal<ScreenInfo[]>(native.screens(), { equals: false });
globalThis.__halo.onScreens = (list) => screenList.set(list);

/** The connected displays, updated when displays change. */
export const screens: Accessor<ScreenInfo[]> = screenList;

/** Props of `<PerScreen>`. */
export interface PerScreenProps {
  /** Called once per display; return its surfaces. */
  children: (screen: ScreenInfo) => Element;
}

/** Renders its children once per display, and disposes an instance when its display goes away. */
export function PerScreen(props: PerScreenProps): null {
  const owner = getOwner();
  const instances = new Map<number, () => void>();
  effect(() => {
    const list = screens();
    const ids = new Set(list.map((screen) => screen.id));
    for (const [id, dispose] of instances) {
      if (ids.has(id)) continue;
      dispose();
      instances.delete(id);
    }
    for (const screen of list) {
      if (instances.has(screen.id)) continue;
      runWithOwner(owner, () =>
        root((dispose) => {
          instances.set(screen.id, dispose);
          try {
            untrack(() => props.children(screen));
          } catch (error) {
            reportError(error);
          }
        }),
      );
    }
  });
  return null;
}
