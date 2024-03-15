import { Tables } from "@/lib/database.types";

export const PHYSICAL_REGION_PATH: SearchFilterName = "physical_region_path";

export const createRegionFilter = (
  params: URLSearchParams,
  regions: Tables<"region_used">[]
): SearchFilter => {
  const region = params.get(PHYSICAL_REGION_PATH);
  return {
    type: "radio",
    name: PHYSICAL_REGION_PATH,
    label: "Region",
    options: [
      {
        label: "Missing",
        value: null,
        humanReadableValue: "Missing",
        className: "bg-orange-200",
      },
      ...regions.map(({ code, path, name }) => ({
        label: `${code} ${name}`,
        value: path as string,
        humanReadableValue: `${code} ${name}`,
      })),
    ],
    selected: region ? [region === "null" ? null : region] : [],
  };
};
