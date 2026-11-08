import { createHash } from "node:crypto";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import type { AddressInfo } from "node:net";
import { JSDOM } from "jsdom";
import { Agent, fetch } from "undici";
import { contactInfoSchema } from "@/app/legal-units/[id]/contact/validation";

// Resolve the sanitizer from Mermaid's dependency graph, as the diagram does.
const mermaidRequire = createRequire(require.resolve("mermaid"));
const createDOMPurify = mermaidRequire("dompurify") as (
  window: JSDOM["window"]
) => {
  sanitize: (node: Node | string, options?: Record<string, unknown>) => string;
};

describe("dependency security compatibility", () => {
  test("HTTP integrity verifies pinned bytes for every supported token casing", async () => {
    const body = "statbus authenticated response";
    const server = createServer((_request, response) => response.end(body));
    await new Promise<void>((resolve) =>
      server.listen(0, "127.0.0.1", resolve)
    );
    const dispatcher = new Agent();
    const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;

    try {
      for (const algorithm of ["sha256", "SHA256", "Sha256"]) {
        const digest = createHash("sha256").update(body).digest("base64");
        const response = await fetch(url, {
          dispatcher,
          integrity: `${algorithm}-${digest}`,
        });
        expect(await response.text()).toBe(body);

        const wrongDigest = createHash("sha256")
          .update("different bytes")
          .digest("base64");
        await expect(
          fetch(url, { dispatcher, integrity: `${algorithm}-${wrongDigest}` })
        ).rejects.toThrow("fetch failed");
      }
    } finally {
      await dispatcher.close();
      await new Promise<void>((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve()))
      );
    }
  });

  test("diagram sanitizer preserves SVG labels and safe links", () => {
    const { window } = new JSDOM("");
    try {
      const purify = createDOMPurify(window);
      const clean = purify.sanitize(
        '<svg xmlns="http://www.w3.org/2000/svg"><a href="https://example.org/schema"><text>Legal unit</text></a><script>alert(1)</script></svg>'
      );
      const document = new window.DOMParser().parseFromString(
        clean,
        "image/svg+xml"
      );
      expect(document.documentElement.localName).toBe("svg");
      expect(document.querySelector("text")?.textContent).toBe("Legal unit");
      expect(document.querySelector("a")?.getAttribute("href")).toBe(
        "https://example.org/schema"
      );
      expect(
        Array.from(document.documentElement.children, (node) => node.localName)
      ).toEqual(["a"]);
    } finally {
      window.close();
    }
  });

  test("template-safe sanitization neutralizes split shadow-root expressions", () => {
    const { window } = new JSDOM("");
    try {
      const host = window.document.createElement("div");
      const shadow = host.attachShadow({ mode: "open" });
      shadow.append(
        window.document.createTextNode("$"),
        window.document.createElement("object"),
        window.document.createTextNode("{alert(document.domain)}")
      );
      createDOMPurify(window).sanitize(host, {
        IN_PLACE: true,
        SAFE_FOR_TEMPLATES: true,
      });
      expect(shadow.textContent).toBe(" ");
    } finally {
      window.close();
    }
  });

  test("Mermaid accepts the database ER diagram syntax and ELK configuration", () => {
    const output = execFileSync(
      process.execPath,
      [
        "--input-type=module",
        "-e",
        `
      import mermaid from 'mermaid';
      mermaid.initialize({ startOnLoad: false, maxTextSize: 500000 });
      const result = await mermaid.parse('---\\nconfig:\\n    layout: elk\\n---\\nerDiagram\\n  legal_unit ||--o{ establishment : contains\\n  legal_unit {\\n    int id PK\\n    string name\\n  }');
      console.log(result.diagramType);
    `,
      ],
      { cwd: process.cwd(), encoding: "utf8" }
    );
    expect(output.trim()).toBe("er");
  });

  test("v3 form validation retains date, nullable source and optional field coercion", () => {
    const form = new FormData();
    form.set("email_address", "registry@example.org");
    form.set("data_source_id", "");
    form.set("valid_from", "2026-11-08");
    form.set("valid_to", "");
    expect(contactInfoSchema.parse(form)).toEqual({
      email_address: "registry@example.org",
      data_source_id: null,
      valid_from: "2026-11-08",
      valid_to: "infinity",
    });

    form.set("valid_from", "not-a-date");
    const result = contactInfoSchema.safeParse(form);
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues.map((issue) => issue.path)).toEqual([
        ["valid_from"],
      ]);
    }
  });
});
