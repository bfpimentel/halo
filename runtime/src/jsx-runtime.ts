import type { Element as HaloElement } from "./components";
import { untrack } from "./reactive";

type Component<P> = (props: P) => HaloElement;

export function jsx<P>(type: Component<P>, props: P): HaloElement {
  if (typeof type !== "function") throw new Error(`halo: unknown element <${String(type)}>; use the components exported by "halo"`);
  return untrack(() => type(props));
}

export const jsxs = jsx;

export function Fragment(props: { children?: HaloElement }): HaloElement {
  return props.children;
}

export declare namespace JSX {
  type Element = HaloElement;
  interface IntrinsicElements {}
  interface ElementChildrenAttribute {
    children: {};
  }
}
