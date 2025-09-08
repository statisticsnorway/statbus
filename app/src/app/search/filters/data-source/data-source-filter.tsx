"use client";
import DataSourceOptions from "@/app/search/filters/data-source/data-source-options";
import { useSearchPageData } from "@/atoms/search";

export default function DataSourceFilter() {
  const { allDataSources } = useSearchPageData();

  return (
    <DataSourceOptions
      dataSources={allDataSources ?? []}
      options={
        allDataSources?.map(({ code, name }) => ({
          label: name!,
          value: code!,
          humanReadableValue: name!,
        })) ?? []
      }
    />
  );
}
