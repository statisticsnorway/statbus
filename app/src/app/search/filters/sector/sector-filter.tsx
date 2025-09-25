"use client";
import SectorOptions from "@/app/search/filters/sector/sector-options";
import { useSearchPageData } from "@/atoms/search";

export default function SectorFilter() {
  const { allSectors } = useSearchPageData();

  return (
    <SectorOptions
      options={
        allSectors?.map(({ code, path, name }) => ({
          label: code ? `${code} ${name}` : `${name}`,
          value: path as string,
          humanReadableValue: code ? `${code} ${name}` : `${name}`,
        })) ?? []
      }
    />
  );
}
