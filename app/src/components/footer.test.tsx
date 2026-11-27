/**
 * Footer version text (STATBUS-422). Finland's fresh v2026.10.0 install
 * (bce5bf39) rendered "Statbus version unknown (bce5bf39)" because the
 * footer ignored the install-time PUBLIC_STATBUS_VERSION whenever the ledger
 * had no release identity for the artifact. Rendered statically (node
 * environment, effects never run); the injected runtime config is mocked.
 */
import { renderToStaticMarkup } from "react-dom/server";
import { Provider, createStore } from "jotai";
import { artifactSHAAtom, runningIdentityAtom } from "@/atoms/running-identity";

const mockConfig = {
  fallbackVersion: "",
  fallbackCommit: "",
  deploymentSlotName: "",
};
jest.mock("@/lib/statbus-config", () => ({ statbusConfig: mockConfig }));
const mockCountry: { current: { name: string; iso_2: string } | null } = {
  current: null,
};
jest.mock("@/atoms/getting-started", () => {
  const { atom } = require("jotai");
  return { installationCountryAtom: atom(() => mockCountry.current) };
});
jest.mock(
  "@/components/command-palette/command-palette-trigger-button",
  () => ({ CommandPaletteTriggerButton: () => null })
);
jest.mock("@/atoms/auth", () => {
  const { atom } = require("jotai");
  return { isAuthenticatedStrictAtom: atom(false) };
});

const Footer = require("./footer").default as typeof import("./footer").default;

const BCE = "bce5bf39b73fcb87ee55900fab927c36872e23c0";

function footerText(version: string, commit: string): string {
  mockConfig.fallbackVersion = version;
  mockConfig.fallbackCommit = commit;
  const store = createStore();
  store.set(artifactSHAAtom, BCE);
  return renderToStaticMarkup(
    <Provider store={store}>
      <Footer />
    </Provider>
  )
    .replace(/<[^>]+>/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

test("released install shows its release and commit", () => {
  expect(footerText("v2026.10.0", "bce5bf39")).toContain(
    "Statbus version v2026.10.0 (bce5bf39)"
  );
});

test("ledger identity still names the artifact", () => {
  mockConfig.fallbackVersion = "";
  mockConfig.fallbackCommit = "";
  const store = createStore();
  store.set(artifactSHAAtom, BCE);
  store.set(runningIdentityAtom, {
    commit_sha: BCE,
    resolved_name: "v2026.10.0",
    release_status: "release",
    build_name: "v2026.10.0-rc.20",
  });
  const html = renderToStaticMarkup(
    <Provider store={store}>
      <Footer />
    </Provider>
  );
  expect(html).toContain("/releases/tag/v2026.10.0");
  expect(html.replace(/<[^>]+>/g, "")).toContain("v2026.10.0");
});

test.each(["", "local"])(
  "unknown version (%j) with known commit shows the commit, never 'unknown'",
  (version) => {
    const text = footerText(version, "bce5bf39");
    expect(text).toContain("Statbus version commit bce5bf39");
    expect(text).not.toContain("unknown");
  }
);

// p9xte6: which installation this is, at a glance: the configured country's flag and the slot's
// name, before the version.
function installationHtml(
  country: { name: string; iso_2: string } | null,
  name: string
): string {
  mockCountry.current = country;
  mockConfig.deploymentSlotName = name;
  const html = renderToStaticMarkup(
    <Provider store={createStore()}>
      <Footer />
    </Provider>
  );
  // The installation part: from its marker's tag up to the GitHub link that follows it.
  const start = html.indexOf("data-installation");
  if (start < 0) return "";
  const end = html.lastIndexOf("<a", html.indexOf("Github Repository", start));
  return html.slice(html.indexOf(">", start) + 1, end);
}

test("an installation in Mozambique shows its flag and its name", () => {
  const html = installationHtml(
    { name: "Mozambique", iso_2: "MZ" },
    "Mozambique"
  );
  expect(html).toContain('aria-label="Mozambique"');
  expect(html).toContain("🇲🇿");
  expect(html.replace(/<[^>]+>/g, "")).toBe("🇲🇿Mozambique");
});

test("with no country the footer shows the name only, with no empty flag", () => {
  const html = installationHtml(null, "Development");
  expect(html).not.toContain('role="img"');
  expect(html.replace(/<[^>]+>/g, "")).toBe("Development");
});
