import { editChangesEnterprise } from "./primary-unit-flow";

// ep47vn: the notice beside Save names the enterprise only for fields that
// flow to it (doc/primary-units.md, public.timeline_enterprise_def).
describe("editChangesEnterprise", () => {
  it.each([
    ["physical-location"],
    ["postal-location"],
    ["contact-info"],
    ["demographic"],
    ["primary_category_id"],
    ["secondary_category_id"],
    ["sector_id"],
  ])("%s on a primary legal unit or establishment changes the enterprise", (field) => {
    expect(editChangesEnterprise(field, "legal_unit", false)).toBe(true);
    expect(editChangesEnterprise(field, "establishment", false)).toBe(true);
  });

  it("the name changes the enterprise only while the enterprise has no short name", () => {
    expect(editChangesEnterprise("name", "legal_unit", false)).toBe(true);
    expect(editChangesEnterprise("name", "legal_unit", true)).toBe(false);
  });

  it("legal form flows from a primary legal unit only", () => {
    expect(editChangesEnterprise("legal_form_id", "legal_unit", false)).toBe(true);
    expect(editChangesEnterprise("legal_form_id", "establishment", false)).toBe(false);
  });

  it.each([["tax_ident"], ["employees"], ["turnover"], ["image"]])(
    "%s (identifiers, statistics, image) does not change the enterprise",
    (field) => {
      expect(editChangesEnterprise(field, "legal_unit", false)).toBe(false);
    }
  );
});
