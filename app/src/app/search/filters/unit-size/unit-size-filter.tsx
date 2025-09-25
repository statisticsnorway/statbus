"use client";
import UnitSizeOptions from "@/app/search/filters/unit-size/unit-size-options";
import { useSearchPageData } from "@/atoms/search";

export default function UnitSizeFilter() {
  const { allUnitSizes } = useSearchPageData();

  return (
    <UnitSizeOptions
      options={
        allUnitSizes?.map(({ code, name }) => ({
          label: name!,
          value: code!,
          humanReadableValue: name!,
        })) ?? []
      }
    />
  );
}
