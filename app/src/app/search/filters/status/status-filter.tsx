"use client";
import StatusOptions from "@/app/search/filters/status/status-options";
import { useSearchPageData } from "@/atoms/search";

export default function StatusFilter() {
  const { allStatuses } = useSearchPageData();

  return (
    <StatusOptions
      options={
        allStatuses?.map(({ code, name }) => ({
          label: name!,
          value: code!,
          humanReadableValue: name!,
        })) ?? []
      }
    />
  );
}
