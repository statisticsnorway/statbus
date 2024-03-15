import { Tables } from "@/lib/database.types";

export const SECTOR_CODE: SearchFilterName = "sector_code";

export const createSectorFilter = (
  params: URLSearchParams,
  sectors: Tables<"sector">[]
): SearchFilter => {
  const sectorCode = params.get(SECTOR_CODE);
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
