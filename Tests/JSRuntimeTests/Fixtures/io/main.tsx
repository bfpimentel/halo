import { readFile, spawn, watchFile, writeFile } from "halo";
import { effect } from "halo/signals";

const { dir } = (globalThis as any).__input as { dir: string };
const state = {
  lines: [] as string[],
  errors: [] as string[],
  exits: [] as number[],
  background: [] as string[],
  watched: [] as (string | null)[],
  read: "",
  written: false,
  failures: [] as string[],
};
(globalThis as any).__test = state;

spawn("/bin/sh", ["-c", 'printf "a\\nb\\r\\nc"; echo oops >&2; exit 3'], {
  onLine: (line) => state.lines.push(line),
  onError: (line) => state.errors.push(line),
  onExit: (code) => state.exits.push(code),
});
spawn("/bin/sh", ["-c", "sleep 30 & echo $!; wait"], {
  onLine: (line) => state.background.push(line),
});

readFile("data.txt").then(
  (text) => (state.read = text),
  (error) => state.failures.push(String(error)),
);
writeFile(`${dir}/nested/out.txt`, "hi").then(
  () => (state.written = true),
  (error) => state.failures.push(String(error)),
);
readFile(`${dir}/missing.txt`).catch(() => state.failures.push("missing"));

const watched = watchFile(`${dir}/watched.txt`);
effect(() => state.watched.push(watched() ?? null));

export default () => null;
