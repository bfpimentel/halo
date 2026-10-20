import { describe, expect, test } from "bun:test";
import {
  addInstance,
  duplicateInstance,
  guessValue,
  isSelected,
  parseConfig,
  parseEdit,
  removeInstance,
  removeProp,
  renameInstance,
  serialize,
  setProp,
  splitProps,
  toggleScreen,
  uniqueName,
  widgetNames,
  type Config,
} from "halo/settings/model";

const base = (): Config => ({
  widgets: {
    bar: { widget: "bar", props: { height: 32, label: "x", nested: { a: 1 } } },
    clock: { widget: "clock", screens: [1] },
  },
});

describe("settings model", () => {
  test("parses only configs it can rewrite", () => {
    expect(parseConfig("{")).toHaveProperty("error");
    expect(parseConfig("[]")).toHaveProperty("error");
    expect(parseConfig('{ "widgets": { "a": {} } }')).toHaveProperty("error");
    expect(parseConfig(serialize(base()))).toEqual({ config: base() });
    expect(serialize(base()).endsWith("}\n")).toBe(true);
  });

  test("lists widget files and folders with an index", () => {
    const names = widgetNames(
      [
        { name: "clock.tsx", isDirectory: false },
        { name: "notes.md", isDirectory: false },
        { name: "bar", isDirectory: true },
        { name: "lib", isDirectory: true },
        { name: ".hidden.tsx", isDirectory: false },
      ],
      (folder) => folder === "bar",
    );
    expect(names).toEqual(["bar", "clock"]);
  });

  test("names stay unique and renames keep their position", () => {
    expect(uniqueName(base(), "bar")).toBe("bar-2");
    expect(uniqueName(base(), "osd")).toBe("osd");

    const added = addInstance(base(), "clock");
    expect(added.name).toBe("clock-2");
    expect(Object.keys(added.config.widgets)).toEqual(["bar", "clock", "clock-2"]);

    const copy = duplicateInstance(base(), "bar");
    expect(copy.name).toBe("bar-2");
    expect(Object.keys(copy.config.widgets)).toEqual(["bar", "bar-2", "clock"]);
    expect(copy.config.widgets["bar-2"]).toEqual(base().widgets.bar!);
    expect(copy.config.widgets["bar-2"]).not.toBe(copy.config.widgets.bar);

    const renamed = renameInstance(base(), "bar", "top");
    expect("config" in renamed && Object.keys(renamed.config.widgets)).toEqual([
      "top",
      "clock",
    ]);
    expect(renameInstance(base(), "bar", "clock")).toHaveProperty("error");
    expect(renameInstance(base(), "bar", "  ")).toHaveProperty("error");

    expect(Object.keys(removeInstance(base(), "bar").widgets)).toEqual(["clock"]);
  });

  test("screen chips", () => {
    expect(toggleScreen(undefined, 2)).toEqual([2]);
    expect(toggleScreen("main", 2)).toEqual([2]);
    expect(toggleScreen([2], 1)).toEqual([1, 2]);
    expect(toggleScreen([1, 2], 2)).toEqual([1]);
    expect(toggleScreen([1], 1)).toBe("all");
    expect(toggleScreen([1], "main")).toBe("main");
    expect(isSelected(undefined, "all")).toBe(true);
    expect(isSelected([1], 1)).toBe(true);
    expect(isSelected([1], "all")).toBe(false);
  });

  test("props", () => {
    expect(splitProps(base().widgets.bar!.props)).toEqual({
      flat: [
        ["height", 32],
        ["label", "x"],
      ],
      nested: ["nested"],
    });
    expect(parseEdit("48", 32)).toEqual({ value: 48 });
    expect(parseEdit("tall", 32)).toHaveProperty("error");
    expect(parseEdit("", 32)).toHaveProperty("error");
    expect(parseEdit("12", "x")).toEqual({ value: "12" });
    expect(guessValue("true")).toBe(true);
    expect(guessValue("1.5")).toBe(1.5);
    expect(guessValue("HH:mm")).toBe("HH:mm");

    const set = setProp(base(), "clock", "size", 48);
    expect(set.widgets.clock!.props).toEqual({ size: 48 });
    expect(removeProp(set, "clock", "size").widgets.clock).toEqual({
      widget: "clock",
      screens: [1],
    });
  });
});
