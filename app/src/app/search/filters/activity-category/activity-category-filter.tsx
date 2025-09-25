"use client";
import ActivityCategoryOptions from "@/app/search/filters/activity-category/activity-category-options";
import { useSearchPageData } from "@/atoms/search";

export default function ActivityCategoryFilter() {
  const { allActivityCategories } = useSearchPageData();

  return (
    <ActivityCategoryOptions
      options={[
        {
          label: "Missing",
          value: null,
          humanReadableValue: "Missing",
          className: "bg-orange-200",
        },
        ...(allActivityCategories?.map(({ code, path, name }) => ({
          label: `${code} ${name}`,
          value: path as string,
          humanReadableValue: `${code} ${name}`,
        })) ?? []),
      ]}
    />
  );
}
