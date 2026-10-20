// Builds the docs site into site/dist: guides from docs/*.md, the API reference from the runtime's JSDoc
// (TypeDoc), and the CLI reference from `halo help`'s source. Fails when a public export has no doc comment.

import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { marked } from "marked";
import {
  Application,
  Comment,
  ReflectionKind,
  type DeclarationReflection,
  type SignatureReflection,
} from "typedoc";

const repo = join(import.meta.dir, "..");
const docs = join(repo, "docs");
const out = join(import.meta.dir, "dist");
const github = "https://github.com/bfpimentel/halo";
/** The release tag being built (`vX.Y.Z`, served at the site root) or "next" (`main`, served at `/next/`). */
const version = process.env.HALO_DOCS_VERSION ?? "next";
const released = /^v\d/.test(version);
const ref = released ? version : "main";
// Inlined so the wordmark follows the page's color scheme (WebKit ignores it inside <img> SVGs).
const logo = readFileSync(join(docs, "assets", "logo.svg"), "utf8")
  .replace(/<style>[\s\S]*?<\/style>/, "")
  .replace("<text ", '<text fill="currentColor" font-size="56" font-weight="700" ');
const inlineLogo = (html: string) =>
  html.replace(/<img src="[^"]*logo\.svg" alt="halo">/g, logo);

interface Page {
  path: string;
  title: string;
  html: string;
}

const modules = [
  { file: "index", name: "halo" },
  { file: "signals", name: "halo/signals" },
  { file: "services", name: "halo/services" },
];
const referencePath = (module: string) => `reference/${module.replace("/", "-")}.html`;

const escape = (text: string) =>
  text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

const slug = (text: string) =>
  text
    .toLowerCase()
    .replace(/<[^>]+>/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");

marked.use({
  renderer: {
    heading({ tokens, depth }) {
      const html = this.parser.parseInline(tokens);
      return `<h${depth} id="${slug(html)}">${html}</h${depth}>\n`;
    },
  },
});

const prose = (markdown: string) => marked.parse(markdown, { async: false });

// MARK: Examples

const examplesDir = join(repo, "examples");
/** Capture specs for scripts/screenshots.sh; an optional `title` overrides the folder name. */
const manifest = JSON.parse(
  readFileSync(join(import.meta.dir, "examples.json"), "utf8"),
) as Record<string, { title?: string }>;

/** Demo media for an example: a looping video when there's one, else the screenshot. */
function demo(name: string, root: string, label: string): string {
  const base = join(docs, "assets", "examples", name);
  const src = `${root}assets/examples/${name}`;
  if (existsSync(`${base}.mp4`))
    return `<video src="${src}.mp4" autoplay loop muted playsinline aria-label="${escape(label)}"></video>`;
  if (existsSync(`${base}.png`)) return `<img src="${src}.png" alt="${escape(label)}">`;
  return "";
}

/** An example's halo.json first, then its .ts/.tsx files (top level before widgets/), as paths relative to it. */
function sourceFiles(folder: string, prefix = ""): string[] {
  const entries = readdirSync(join(folder, prefix), { withFileTypes: true });
  const files = entries
    .filter((entry) => entry.isFile() && /\.tsx?$|^halo\.json$/.test(entry.name))
    .map((entry) => prefix + entry.name)
    .sort((a, b) =>
      a.endsWith("halo.json") ? -1 : b.endsWith("halo.json") ? 1 : a.localeCompare(b),
    );
  const folders = entries
    .filter((entry) => entry.isDirectory() && entry.name !== "node_modules")
    .map((entry) => entry.name)
    .sort();
  return [
    ...files,
    ...folders.flatMap((name) => sourceFiles(folder, `${prefix}${name}/`)),
  ];
}

/**
 * The gallery and one page per example. Order and descriptions come from the table in examples/README.md (also what
 * GitHub shows); an example's own README.md adds setup notes; halo.json and every .ts/.tsx file are shown in full.
 */
function examples(): Page[] {
  const table = readFileSync(join(examplesDir, "README.md"), "utf8");
  const rows = [
    ...table.matchAll(/^\| \[`([\w-]+)`\]\([^)]*\)\s*\|\s*(.+?)\s*\|$/gm),
  ].map(([, name, text]) => ({
    name: name ?? "",
    text: text ?? "",
  }));
  const pages: Page[] = [];
  const cards: string[] = [];
  for (const { name, text } of rows) {
    const folder = join(examplesDir, name);
    const notes = existsSync(join(folder, "README.md"))
      ? readFileSync(join(folder, "README.md"), "utf8")
      : "";
    const title =
      notes.match(/^# (.+)$/m)?.[1] ??
      manifest[name]?.title ??
      name.charAt(0).toUpperCase() + name.slice(1);
    const description = marked.parseInline(text, { async: false });
    const files = sourceFiles(folder);
    const sources = files
      .map((file) => {
        const code = readFileSync(join(folder, file), "utf8");
        const href = `${github}/blob/${ref}/examples/${name}/${file}`;
        const language = file.endsWith(".json") ? "json" : "tsx";
        return `<h3 id="${slug(file)}"><a href="${href}"><code>${file}</code></a></h3>${prose("```" + language + "\n" + code + "\n```")}`;
      })
      .join("");
    const run = prose(
      "```bash\nswift run halo start --config examples/" +
        name +
        '                         # from a clone\nhalo start --config "$(brew --prefix)/share/halo/examples/' +
        name +
        '"   # Homebrew\n```',
    );
    pages.push({
      path: `examples/${name}.html`,
      title,
      html:
        `<h1>${escape(title)}</h1><p>${description}</p>${demo(name, "../", title)}` +
        prose(notes.replace(/^# .+\n/, "")) +
        `<h2 id="run">Run it</h2>${run}<h2 id="source">Source</h2>${sources}`,
    });
    cards.push(
      `<a class="card" href="${name}.html">${demo(name, "../", title)}<strong>${escape(title)}</strong><span>${description}</span></a>`,
    );
  }
  pages.unshift({
    path: "examples/index.html",
    title: "Gallery",
    html:
      `<h1>Examples</h1><p>Complete configs from <a href="${github}/tree/${ref}/examples"><code>examples/</code></a>, ` +
      `recorded as they run. Copy any of them into your config folder and change what you like.</p>` +
      `<div class="gallery">${cards.join("")}</div>`,
  });
  return pages;
}

// MARK: Guides

function guides(): Page[] {
  const pages: Page[] = [];
  const home = readFileSync(join(docs, "index.md"), "utf8");
  pages.push({ path: "index.html", title: "halo", html: prose(home) });
  for (const file of readdirSync(join(docs, "guide")).sort()) {
    if (!file.endsWith(".md")) continue;
    const markdown = readFileSync(join(docs, "guide", file), "utf8");
    const title = markdown.match(/^# (.+)$/m)?.[1] ?? file;
    const slug = file.replace(/^\d+-/, "").replace(/\.md$/, "");
    pages.push({ path: `guide/${slug}.html`, title, html: prose(markdown) });
  }
  return pages;
}

// MARK: API reference

async function reference(): Promise<Page[]> {
  const runtime = join(repo, "runtime");
  const app = await Application.bootstrap({
    entryPoints: modules.map((module) => join(runtime, "src", `${module.file}.ts`)),
    tsconfig: join(runtime, "tsconfig.json"),
    excludeInternal: true,
    logLevel: "Warn",
  });
  const project = await app.convert();
  if (!project) throw new Error("TypeDoc couldn't convert the runtime");

  const declarations = new Map<string, DeclarationReflection[]>();
  for (const module of project.children ?? []) {
    const entry = modules.find((candidate) => candidate.file === module.name);
    if (entry) declarations.set(entry.name, module.children ?? []);
  }

  const anchors = new Map<string, string>();
  for (const [module, children] of declarations) {
    for (const child of children)
      anchors.set(child.name, `${referencePath(module)}#${child.name}`);
  }

  const missing: string[] = [];
  const pages: Page[] = [];
  for (const { name: module } of modules) {
    const children = declarations.get(module) ?? [];
    const groups: [string, (child: DeclarationReflection) => boolean][] = [
      ["Components", (c) => c.kindOf(ReflectionKind.Function) && /^[A-Z]/.test(c.name)],
      ["Functions", (c) => c.kindOf(ReflectionKind.Function) && /^[a-z]/.test(c.name)],
      ["Values", (c) => c.kindOf(ReflectionKind.Variable)],
      ["Interfaces", (c) => c.kindOf(ReflectionKind.Interface)],
      ["Types", (c) => c.kindOf(ReflectionKind.TypeAlias)],
    ];
    let html = `<h1><code>${module}</code></h1>`;
    for (const [title, belongs] of groups) {
      const members = children
        .filter(belongs)
        .sort((a, b) => a.name.localeCompare(b.name));
      if (!members.length) continue;
      html += `<h2>${title}</h2>`;
      for (const member of members) {
        const summary = text(member.signatures?.[0]?.comment ?? member.comment);
        if (!summary) missing.push(`${module}: ${member.name}`);
        html += declaration(member, summary, anchors, referencePath(module));
      }
    }
    pages.push({ path: referencePath(module), title: module, html });
  }

  if (missing.length) {
    throw new Error(`Public exports without a doc comment:\n  ${missing.join("\n  ")}`);
  }
  return pages;
}

function text(
  comment: { summary: Parameters<typeof Comment.combineDisplayParts>[0] } | undefined,
) {
  return comment ? Comment.combineDisplayParts(comment.summary).trim() : "";
}

/** Type text with every documented name linked to its entry. */
function linked(type: string, anchors: Map<string, string>, from: string) {
  const prefix = from.split("/").length > 1 ? "../" : "";
  return escape(type).replace(/\b[A-Z][A-Za-z]+\b/g, (name) => {
    const anchor = anchors.get(name);
    return anchor ? `<a href="${prefix}${anchor}">${name}</a>` : name;
  });
}

function signature(name: string, signature: SignatureReflection) {
  const generics = signature.typeParameters?.length
    ? `<${signature.typeParameters.map((parameter) => parameter.name).join(", ")}>`
    : "";
  const parameters = (signature.parameters ?? [])
    .map((parameter) => {
      const optional = parameter.flags.isOptional || parameter.defaultValue ? "?" : "";
      return `${parameter.name}${optional}: ${parameter.type?.toString() ?? "unknown"}`;
    })
    .join(", ");
  return `${name}${generics}(${parameters}): ${signature.type?.toString() ?? "void"}`;
}

function declaration(
  member: DeclarationReflection,
  summary: string,
  anchors: Map<string, string>,
  page: string,
) {
  let code: string;
  if (member.signatures?.length) {
    code = member.signatures
      .map((each) => `function ${signature(member.name, each)}`)
      .join("\n");
  } else if (member.kindOf(ReflectionKind.Variable)) {
    code = `const ${member.name}: ${member.type?.toString() ?? "unknown"}`;
  } else if (member.kindOf(ReflectionKind.Interface)) {
    const parents = member.extendedTypes?.map((type) => type.toString()).join(", ");
    code = `interface ${member.name}${parents ? ` extends ${parents}` : ""}`;
  } else {
    const generics = member.typeParameters?.length
      ? `<${member.typeParameters.map((parameter) => parameter.name).join(", ")}>`
      : "";
    code = `type ${member.name}${generics} = ${member.type?.toString() ?? "unknown"}`;
  }

  let html = `<section id="${member.name}"><h3><a href="#${member.name}">${member.name}</a></h3>`;
  html += `<pre><code>${linked(code, anchors, page)}</code></pre>${prose(summary)}`;

  const properties =
    member.children?.filter((child) => !child.name.startsWith("_")) ?? [];
  if (properties.length) {
    html +=
      "<table><thead><tr><th>Property</th><th>Type</th><th>Description</th></tr></thead><tbody>";
    for (const property of properties) {
      const method = property.signatures?.[0];
      const name = method ? `${property.name}()` : property.name;
      const optional = property.flags.isOptional ? "?" : "";
      const type = method
        ? signature(property.name, method).slice(property.name.length)
        : (property.type?.toString() ?? "unknown");
      const description = text(method?.comment ?? property.comment);
      html += `<tr><td><code>${name}${optional}</code></td><td><code>${linked(type, anchors, page)}</code></td><td>${marked.parseInline(description, { async: false })}</td></tr>`;
    }
    html += "</tbody></table>";
  }
  return `${html}</section>`;
}

// MARK: CLI reference

function cli(): Page {
  const source = readFileSync(join(repo, "Sources/IPC/Protocol.swift"), "utf8");
  const usage = source.match(/static let usage = """\n([\s\S]*?)\n\s*"""/)?.[1] ?? "";
  const rows = usage
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("usage:"))
    .map((line) => line.split(/\s{2,}/));
  let html =
    "<h1>CLI</h1><p>One binary, <code>halo</code>. Every command except <code>start</code>, <code>init</code> and <code>version</code> talks to the running host.</p>";
  html += "<table><thead><tr><th>Command</th><th>Does</th></tr></thead><tbody>";
  for (const [command, description] of rows) {
    html += `<tr><td><code>halo ${escape(command)}</code></td><td>${escape(description ?? "")}</td></tr>`;
  }
  return { path: "cli.html", title: "CLI", html: `${html}</tbody></table>` };
}

// MARK: Layout

/** Which docs these are, with a link to the other build: the latest release lives at `/`, `main` at `/next/`. */
function versionNote(root: string): string {
  return released
    ? `<span class="version">${version} · <a href="${root}next/index.html">main branch docs</a></span>`
    : `<span class="version">main (unreleased) · <a href="${root}../index.html">latest release docs</a></span>`;
}

function render(page: Page, pages: Page[]) {
  const root = "../".repeat(page.path.split("/").length - 1);
  const link = (target: Page) =>
    `<a href="${root}${target.path}"${target.path === page.path ? ' class="current"' : ""}>${target.title}</a>`;
  const guide = pages.filter((each) => each.path.startsWith("guide/")).map(link);
  const gallery = pages.filter((each) => each.path.startsWith("examples/")).map(link);
  const api = pages.filter((each) => each.path.startsWith("reference/")).map(link);
  const cliPage = pages.find((each) => each.path === "cli.html");
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${page.path === "index.html" ? "halo: TSX widgets for macOS" : page.path.startsWith("reference/") ? `${page.title} reference` : `${page.title} · halo`}</title>
<link rel="stylesheet" href="${root}style.css">
<link rel="icon" href="${root}assets/favicon.svg" type="image/svg+xml">
<link rel="icon" href="${root}assets/favicon.png" sizes="32x32" type="image/png">
<link rel="apple-touch-icon" href="${root}assets/apple-touch-icon.png">
</head>
<body>
${
  page.path === "index.html"
    ? `<main class="landing">${page.html}</main>
<footer><a href="guide/getting-started.html">Docs</a><a href="examples/index.html">Examples</a><a href="reference/halo.html">API</a><a href="cli.html">CLI</a><a href="${github}">GitHub</a>${versionNote(root)}</footer>`
    : `<header>
<a class="brand" href="${root}index.html"><img src="${root}assets/logo.svg" alt="halo"></a>
<span>${versionNote(root)}<a href="${github}">GitHub</a></span>
</header>
<div class="layout">
<nav>
<p>Guide</p>${guide.join("")}
<p>Examples</p>${gallery.join("")}
<p>Reference</p>${api.join("")}${cliPage ? link(cliPage) : ""}
</nav>
<main>${page.html}</main>
</div>`
}
</body>
</html>
`;
}

// MARK: Build

const pages = [...guides(), ...examples(), ...(await reference()), cli()];
rmSync(out, { recursive: true, force: true });
for (const page of pages) {
  const file = join(out, page.path);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, inlineLogo(render(page, pages)));
}
cpSync(join(import.meta.dir, "style.css"), join(out, "style.css"));
if (existsSync(join(docs, "assets")))
  cpSync(join(docs, "assets"), join(out, "assets"), { recursive: true });
writeFileSync(join(out, ".nojekyll"), "");
console.log(`site/dist: ${pages.length} pages (${version})`);
