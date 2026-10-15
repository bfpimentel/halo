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

interface Page {
  path: string;
  title: string;
  html: string;
}

const modules = [
  { file: "index", name: "halo" },
  { file: "signals", name: "halo/signals" },
  { file: "services", name: "halo/services" },
  { file: "aerospace", name: "halo/aerospace" },
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

function render(page: Page, pages: Page[]) {
  const root = "../".repeat(page.path.split("/").length - 1);
  const link = (target: Page) =>
    `<a href="${root}${target.path}"${target.path === page.path ? ' class="current"' : ""}>${target.title}</a>`;
  const guide = pages.filter((each) => each.path.startsWith("guide/")).map(link);
  const api = pages.filter((each) => each.path.startsWith("reference/")).map(link);
  const cliPage = pages.find((each) => each.path === "cli.html");
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${page.path === "index.html" ? "halo: TSX widgets for macOS" : page.path.startsWith("reference/") ? `${page.title} reference` : `${page.title} · halo`}</title>
<link rel="stylesheet" href="${root}style.css">
</head>
<body>
<header>
<a class="brand" href="${root}index.html"><img src="${root}assets/logo.svg" alt="halo"></a>
<span><a href="${root}guide/getting-started.html">Docs</a><a href="${github}">GitHub</a></span>
</header>
${
  page.path === "index.html"
    ? `<main class="landing">${page.html}</main>`
    : `<div class="layout">
<nav>
<p>Guide</p>${guide.join("")}
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

const pages = [...guides(), ...(await reference()), cli()];
rmSync(out, { recursive: true, force: true });
for (const page of pages) {
  const file = join(out, page.path);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, render(page, pages));
}
cpSync(join(import.meta.dir, "style.css"), join(out, "style.css"));
if (existsSync(join(docs, "assets")))
  cpSync(join(docs, "assets"), join(out, "assets"), { recursive: true });
writeFileSync(join(out, ".nojekyll"), "");
console.log(`site/dist: ${pages.length} pages`);
