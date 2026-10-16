import { beforeAll, describe, expect, test } from "bun:test";
import type * as Components from "halo/components";
import type * as Reactive from "halo/reactive";

interface FakeNode {
  kind: string;
  text?: string;
  children: number[];
  parent?: number;
}

const nodes = new Map<number, FakeNode>();
const log: string[] = [];
let nextID = 1;

function detach(id: number): void {
  const parent = nodes.get(nodes.get(id)?.parent ?? -1);
  if (parent) parent.children = parent.children.filter((child) => child !== id);
  const node = nodes.get(id);
  if (node) node.parent = undefined;
}

globalThis.__halo = {};
globalThis.__native = {
  log: (_level: string, message: string) => log.push(`error ${message}`),
  screens: () => [],
  listen: () => {},
  setStyle: () => {},
  setProp: (id: number, key: string, value: unknown) => {
    const node = nodes.get(id);
    if (node && key === "text") node.text = String(value);
  },
  createNode: (kind: string) => {
    nodes.set(nextID, { kind, children: [] });
    return nextID++;
  },
  insert: (parent: number, child: number, index: number) => {
    log.push(`insert ${nodes.get(child)?.text ?? child}`);
    detach(child);
    const children = nodes.get(parent)?.children ?? [];
    children.splice(Math.min(index, children.length), 0, child);
    const node = nodes.get(child);
    if (node) node.parent = parent;
  },
  detach,
  destroyNode: (id: number) => {
    log.push(`destroy ${nodes.get(id)?.text ?? id}`);
    detach(id);
    nodes.delete(id);
  },
} as unknown as typeof globalThis.__native;

let components: typeof Components;
let reactive: typeof Reactive;
beforeAll(async () => {
  components = await import("halo/components");
  reactive = await import("halo/reactive");
});

type Item = { id: string; label: string };

function mount(initial: Item[]) {
  const { Box, For, Text } = components;
  const { effect, onCleanup, root, signal } = reactive;
  const items = signal(initial);
  const cleaned: string[] = [];
  let renders = 0;
  let box!: Components.NativeNode;
  const dispose = root((dispose) => {
    box = Box({
      children: [
        "head",
        For({
          each: items,
          key: (item: Item) => item.id,
          children: (item, index) => {
            renders++;
            const id = item().id;
            onCleanup(() => cleaned.push(id));
            const row = Text({ children: () => `${index()}:${item().label}` });
            effect(() => item());
            return row;
          },
        }),
        "tail",
      ],
    });
    return dispose;
  });
  const texts = () => nodes.get(box.id)?.children.map((id) => nodes.get(id)?.text);
  log.length = 0;
  return { items, texts, cleaned, renders: () => renders, dispose };
}

const item = (id: string, label = id) => ({ id, label });

describe("<For>", () => {
  test("renders each key once, in order, between its siblings", () => {
    const list = mount([item("a"), item("b")]);
    expect(list.texts()).toEqual(["head", "0:a", "1:b", "tail"]);
    expect(list.renders()).toBe(2);
    list.dispose();
  });

  test("an insertion in the middle renders only the new row and reindexes the rest", () => {
    const list = mount([item("a"), item("c")]);
    list.items.set([item("a"), item("b"), item("c")]);
    expect(list.texts()).toEqual(["head", "0:a", "1:b", "2:c", "tail"]);
    expect(list.renders()).toBe(3);
    expect(log.filter((line) => line.startsWith("destroy"))).toEqual([]);
    list.dispose();
  });

  test("moves keep their nodes and only insert what changed place", () => {
    const list = mount([item("a"), item("b"), item("c"), item("d")]);
    const before = new Set(nodes.keys());
    list.items.set([item("d"), item("a"), item("b"), item("c")]);
    expect(list.texts()).toEqual(["head", "0:d", "1:a", "2:b", "3:c", "tail"]);
    expect(new Set(nodes.keys())).toEqual(before);
    expect(log.filter((line) => line.startsWith("insert"))).toEqual(["insert 3:d"]);

    list.items.set([item("c"), item("b"), item("a"), item("d")]);
    expect(list.texts()).toEqual(["head", "0:c", "1:b", "2:a", "3:d", "tail"]);
    expect(list.renders()).toBe(4);
    list.dispose();
  });

  test("a kept key gets its new value through the item accessor", () => {
    const list = mount([item("a"), item("b")]);
    list.items.set([item("a", "renamed"), item("b")]);
    expect(list.texts()).toEqual(["head", "0:renamed", "1:b", "tail"]);
    expect(list.renders()).toBe(2);
    list.dispose();
  });

  test("removed keys are disposed: their cleanups run and their nodes are destroyed", () => {
    const list = mount([item("a"), item("b"), item("c")]);
    list.items.set([item("c"), item("a")]);
    expect(list.cleaned).toEqual(["b"]);
    expect(log).toContain("destroy 1:b");
    expect(list.texts()).toEqual(["head", "0:c", "1:a", "tail"]);
    list.dispose();
  });

  test("disposing the owner disposes every row and leaves no nodes", () => {
    const count = nodes.size;
    const list = mount([item("a"), item("b")]);
    list.items.set([item("b"), item("c")]);
    list.dispose();
    expect(list.cleaned.sort()).toEqual(["a", "b", "c"]);
    expect(nodes.size).toBe(count);
  });

  test("a duplicate key is reported and rendered once", () => {
    const list = mount([item("a"), item("a", "again")]);
    expect(list.texts()).toEqual(["head", "0:a", "tail"]);
    list.items.set([item("a"), item("b"), item("b")]);
    expect(log.some((line) => line.includes("duplicate key b"))).toBe(true);
    list.dispose();
  });
});
