import { locationSchema } from "@/app/legal-units/[id]/general-info/validation";

// STATBUS-604: a location form sends "" for fields the user leaves empty. An
// empty optional number means "no value" (null), never 0, and an empty country
// is refused with a message instead of reaching the database as country 0.
const form = (fields: Record<string, string>) => {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) fd.append(k, v);
  return fd;
};
const base = {
  address_part1: "Testveien 1",
  type: "physical",
  valid_from: "2026-01-01",
  valid_to: "",
};

describe("locationSchema", () => {
  it("reads empty region and coordinates as no value", () => {
    const parsed = locationSchema.safeParse(
      form({ ...base, country_id: "167", region_id: "", physical_latitude: "", physical_longitude: "", altitude: "" })
    );
    expect(parsed.success).toBe(true);
    expect(parsed.success && parsed.data).toMatchObject({
      country_id: 167,
      region_id: null,
      physical_latitude: null,
      physical_longitude: null,
      altitude: null,
    });
  });

  it("keeps chosen region and coordinates as numbers", () => {
    const parsed = locationSchema.safeParse(
      form({ ...base, country_id: "167", region_id: "171", physical_latitude: "59.9", physical_longitude: "10.7", altitude: "" })
    );
    expect(parsed.success && parsed.data).toMatchObject({
      region_id: 171,
      physical_latitude: 59.9,
      physical_longitude: 10.7,
      altitude: null,
    });
  });

  it("refuses an empty country with a message naming the field", () => {
    const parsed = locationSchema.safeParse(form({ ...base, country_id: "" }));
    expect(parsed.success).toBe(false);
    expect(!parsed.success && parsed.error.issues.map((i) => [i.path.join("."), i.message])).toEqual([
      ["country_id", "Select a country"],
    ]);
  });
});
