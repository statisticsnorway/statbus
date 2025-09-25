"use client";
import RegionOptions from "@/app/search/filters/region/region-options";
import { useSearchPageData } from "@/atoms/search";

export default function RegionFilter() {
  const { allRegions } = useSearchPageData();

  return (
    <RegionOptions
      options={[
        {
          label: "Missing",
          value: null,
          humanReadableValue: "Missing",
          className: "bg-orange-200",
        },
        ...(allRegions?.map(({ code, path, name }) => ({
          label: code ? `${code} ${name}` : `${name}`,
          value: path as string,
          humanReadableValue: code ? `${code} ${name}` : `${name}`,
        })) ?? []),
      ]}
    />
  );
}
