import { listen, type ClickEvent, type KeyEvent, type ScrollEvent } from "./events";
import { reportError } from "./host";
import { native, type ScreenInfo } from "./native";
import { effect, getOwner, onCleanup, root, runWithOwner, signal, untrack, type Accessor } from "./reactive";

export type Reactive<T> = T | Accessor<T>;

export class NativeNode {
  constructor(readonly id: number) {}
}

export type Element = NativeNode | string | number | boolean | null | undefined | Accessor<unknown> | Element[];

type Color = string;
type Length = number | `${number}%` | "auto";
type Spacing = number | [vertical: number, horizontal: number] | [top: number, right: number, bottom: number, left: number];

export interface BoxStyle {
  flexDirection?: "row" | "column";
  justify?: "start" | "center" | "end" | "space-between" | "space-around" | "space-evenly";
  align?: "start" | "center" | "end" | "stretch";
  padding?: Spacing;
  gap?: number;
  width?: Length;
  height?: Length;
  grow?: number;
  shrink?: number;
  background?: Color;
  borderColor?: Color;
  borderWidth?: number;
  radius?: number;
  opacity?: number;
}

export interface TextStyle extends BoxStyle {
  color?: Color;
  fontSize?: number;
  fontWeight?: "regular" | "medium" | "semibold" | "bold" | number;
  fontFamily?: string;
}

type StyleProp<S> = Reactive<{ [K in keyof S]?: Reactive<S[K]> }>;

function read<T>(value: Reactive<T>): T {
  return typeof value === "function" ? (value as Accessor<T>)() : value;
}

/// Event props shared by Box, Text and Image. Events bubble to the closest ancestor listening for them.
export interface Interactive {
  onClick?: (event: ClickEvent) => void;
  onScroll?: (event: ScrollEvent) => void;
  onHover?: (hovered: boolean) => void;
  ref?: (node: NativeNode) => void;
}

function wire(node: NativeNode, props: Interactive): void {
  listen(node.id, "click", props.onClick);
  listen(node.id, "scroll", props.onScroll);
  listen(node.id, "hover", props.onHover);
  props.ref?.(node);
}

function createNode(kind: "box" | "text" | "image" | "input"): NativeNode {
  const id = native.createNode(kind);
  onCleanup(() => native.destroyNode(id));
  return new NativeNode(id);
}

function applyStyle(node: NativeNode, style: StyleProp<TextStyle> | undefined): void {
  if (!style) return;
  if (typeof style === "function") {
    let previous: string[] = [];
    effect(() => {
      const current = style();
      for (const key of previous) if (!(key in current)) native.setStyle(node.id, key, null);
      for (const [key, value] of Object.entries(current)) native.setStyle(node.id, key, read(value));
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
  else if (children !== null && children !== undefined && children !== false && children !== true) out.push(children);
  return out;
}

function toNodes(value: Element): NativeNode[] {
  return flatten(value).flatMap((item) => {
    if (item instanceof NativeNode) return [item];
    if (typeof item === "function") return toNodes(item() as Element);
    return [Text({ children: String(item) })];
  });
}

/// Static children are inserted once; each function child is a slot re-rendered when what it reads changes.
function appendChildren(parent: NativeNode, children: Element): void {
  const sizes: number[] = [];
  for (const child of flatten(children)) {
    const slot = sizes.length;
    if (typeof child !== "function") {
      const nodes = toNodes(child);
      for (const node of nodes) native.insert(parent.id, node.id, Number.MAX_SAFE_INTEGER);
      sizes.push(nodes.length);
      continue;
    }
    sizes.push(0);
    let current: NativeNode[] = [];
    effect(() => {
      const nodes = toNodes(child() as Element);
      for (const node of current) native.detach(node.id);
      const start = sizes.slice(0, slot).reduce((sum, size) => sum + size, 0);
      nodes.forEach((node, offset) => native.insert(parent.id, node.id, start + offset));
      sizes[slot] = nodes.length;
      current = nodes;
    });
  }
}

export function Box(props: Interactive & { style?: StyleProp<BoxStyle>; children?: Element }): NativeNode {
  const node = createNode("box");
  applyStyle(node, props.style);
  appendChildren(node, props.children);
  wire(node, props);
  return node;
}

/// Function children are re-read reactively: `<Text>{() => `WS ${ws()}`}</Text>`.
export function Text(props: Interactive & { style?: StyleProp<TextStyle>; children?: Element }): NativeNode {
  const node = createNode("text");
  wire(node, props);
  applyStyle(node, props.style);
  const parts = flatten(props.children);
  const render = () => parts.map((part) => String(typeof part === "function" ? part() : part)).join("");
  if (parts.some((part) => typeof part === "function")) effect(() => native.setProp(node.id, "text", render()));
  else native.setProp(node.id, "text", render());
  return node;
}

export function Image(props: Interactive & {
  symbol?: Reactive<string>;
  /// A bundle id ("com.apple.Safari") or an absolute `.app` path.
  app?: Reactive<string>;
  file?: Reactive<string>;
  size?: Reactive<number>;
  color?: Reactive<Color>;
  style?: StyleProp<BoxStyle>;
}): NativeNode {
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

/// A native single-line text field (IME, selection and clipboard included). Needs a `keyboard` surface.
/// `onKeyDown` gets Enter, Escape, ArrowUp, ArrowDown and Tab; return true to stop the default behavior.
export function Input(props: {
  value?: Reactive<string>;
  placeholder?: Reactive<string>;
  autofocus?: boolean;
  style?: StyleProp<TextStyle>;
  onInput?: (value: string) => void;
  onSubmit?: (value: string) => void;
  onKeyDown?: (event: { key: string }) => boolean | void;
  ref?: (node: NativeNode) => void;
}): NativeNode {
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

/// Moves keyboard focus into an `<Input>` (its surface must have focus).
export function focus(node: NativeNode): void {
  native.focus(node.id);
}

export type Edge = "top" | "bottom" | "left" | "right";

export interface Attachment {
  to: NativeNode | undefined;
  side?: "below" | "above" | "left" | "right";
  align?: "start" | "center" | "end";
  offset?: number;
}

export interface SurfaceProps {
  /// Target for `halo show|hide|toggle <name>`; shared by this widget's instance on every display.
  name?: string;
  /// Start hidden the first time this name appears (e.g. a launcher opened by a hotkey).
  defaultHidden?: boolean;
  /// Place next to a node of another surface instead of anchoring to the screen. Needs a fixed `size`.
  attach?: Reactive<Attachment>;
  onKeyDown?: (event: KeyEvent) => boolean | void;
  onFocus?: () => void;
  onBlur?: () => void;
  /// A click anywhere outside this surface, in any app.
  onClickOutside?: () => void;
  screen: Reactive<number | ScreenInfo>;
  anchor?: Reactive<Edge[]>;
  margins?: Reactive<Spacing>;
  size?: Reactive<{ width?: number | "fill"; height?: number | "fill" }>;
  layer?: Reactive<"desktop" | "belowMenu" | "aboveMenu" | "overlay">;
  input?: Reactive<"passthrough" | "hover" | "interactive" | "keyboard">;
  avoid?: Reactive<("notch" | "menuBar")[]>;
  visible?: Reactive<boolean>;
  children?: Element;
}

export function Surface(props: SurfaceProps): null {
  const children = flatten(props.children);
  const content =
    children.length === 1 && children[0] instanceof NativeNode ? children[0] : Box({ children: props.children });

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
  return { node: attach.to.id, side: attach.side, align: attach.align, offset: attach.offset };
}

const screenList = signal<ScreenInfo[]>(native.screens(), { equals: false });
globalThis.__halo.onScreens = (list) => screenList.set(list);

export const screens: Accessor<ScreenInfo[]> = screenList;

/// Instances its children once per display; an instance is disposed when its display goes away.
export function PerScreen(props: { children: (screen: ScreenInfo) => Element }): null {
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
