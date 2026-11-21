/**
 * 64ae2w (owner 2026-11-20 and 2026-11-21): the page's own unit is on top, the
 * open yellow sticky "Notes" with its pencil. Below it, the other units of the
 * chain that have a note follow in the order enterprise, legal unit,
 * establishment, each a small post-it named by its role ("Primary legal unit
 * note"), collapsed, its heading the button that opens it; a unit without a
 * note shows nothing. (Opening a post-it, which shows the unit's name as the
 * link to its page above the note, is checked in the driven browser: the
 * app's Jest environment is node, without a DOM to click in.)
 *
 * The box is rendered with renderToStaticMarkup, each unit's stored note
 * given through a mocked SWR.
 */
import { renderToStaticMarkup } from "react-dom/server";

const notesByUnit: Record<string, { id: number; notes: string; edit_by_user_id: number; edit_at: string } | null> = {
  "enterprise_id-10": { id: 1, notes: "Enterprise: watch the merger", edit_by_user_id: 7, edit_at: "2026-11-20T10:00:00Z" },
  "legal_unit_id-20": { id: 2, notes: "LU: called them 3 Nov", edit_by_user_id: 7, edit_at: "2026-11-20T11:00:00Z" },
  "establishment_id-30": null,
};
jest.mock("swr", () => ({
  __esModule: true,
  default: (key: [string, string, number] | null) => ({
    data: key ? notesByUnit[`${key[1]}-${key[2]}`] : undefined,
    mutate: async () => {},
  }),
}));
jest.mock("jotai", () => ({ ...jest.requireActual("jotai"), useAtomValue: () => ({}) }));
jest.mock("@/atoms/rest-client", () => ({ restClientAtom: {} }));
jest.mock("@/atoms/auth", () => ({ currentUserAtom: {}, usePermission: () => ({ canEdit: true }) }));
jest.mock("@/atoms/base-data", () => ({ useBaseData: () => ({ statbusUsers: [{ id: 7, display_name: "Jørgen" }] }) }));
jest.mock("next/link", () => ({
  __esModule: true,
  default: ({ href, children, ...rest }: { href: string; children: React.ReactNode }) => <a href={href} {...rest}>{children}</a>,
}));

import { UnitNotesBox } from "./unit-notes-box";
import { primaryChain } from "./primary-chain";

const hierarchy = {
  enterprise: {
    id: 10,
    short_name: null,
    establishment: [],
    legal_unit: [{ id: 20, name: "VERIDIT AS", primary_for_enterprise: true, establishment: [{ id: 30, name: "VERIDIT AS avd Oslo", primary_for_legal_unit: true }] }],
  },
};

/** The box's parts top to bottom: the own note as "Notes: <text> (pencil)", a post-it as "<heading> [Show]". */
function parts(html: string) {
  return html
    .split("<section")
    .slice(1)
    .map((part) =>
      part.includes("data-unit-notes-current")
        ? `${part.match(/<h3[^>]*>([^<]+)</)?.[1]}: ${part.match(/data-unit-notes-shown="">([^<]+)</)?.[1] ?? (part.includes("No notes") ? "No notes" : "")}${part.includes("data-unit-notes-edit") ? " (pencil)" : ""}`
        : `${part.match(/data-unit-notes-heading="">([^<]+)</)?.[1]} [${part.match(/(Show|Hide)</)?.[1]}]${part.includes("data-unit-notes-shown") ? " open" : ""}`
    );
}

describe("UnitNotesBox", () => {
  it("on the enterprise's page: its own note on top, then the primary legal unit's post-it; the establishment without a note shows nothing", () => {
    const html = renderToStaticMarkup(<UnitNotesBox chain={primaryChain(hierarchy, { column: "enterprise_id", id: 10 })} />);
    expect(parts(html)).toEqual(["Notes: Enterprise: watch the merger (pencil)", "Primary legal unit note [Show]"]);
  });

  it("on the primary establishment's page without a note: 'No notes' on top, then the enterprise's and the legal unit's post-its in that order", () => {
    const html = renderToStaticMarkup(<UnitNotesBox chain={primaryChain(hierarchy, { column: "establishment_id", id: 30 })} />);
    expect(parts(html)).toEqual(["Notes: No notes (pencil)", "Enterprise note [Show]", "Primary legal unit note [Show]"]);
  });

  it("on the primary legal unit's page: its own note on top, then the enterprise's post-it", () => {
    const html = renderToStaticMarkup(<UnitNotesBox chain={primaryChain(hierarchy, { column: "legal_unit_id", id: 20 })} />);
    expect(parts(html)).toEqual(["Notes: LU: called them 3 Nov (pencil)", "Enterprise note [Show]"]);
  });
});
