import { Tables } from "@/lib/database.types";
import { createURLParamsResolver } from "@/app/search/filters/url-params-resolver";

export const SECTOR_CODE: SearchFilterName = "sector_code";

export const createSectorFilter = (
  params: URLSearchParams,
  sectors: Tables<"sector">[]
): SearchFilter => {
  const [sectorCode] = createURLParamsResolver(params)(SECTOR_CODE);
  return {
    type: "options",
    name: SECTOR_CODE,
    label: "Sector",
    options: [
      ...sectors.map(({ code, name }) => ({
        label: `${code} ${name}`,
        value: code,
      })),
    ],
    selected: sectorCode?.split(",") ?? [],
  };
};
