import { createSupabaseSSRClient } from "@/utils/supabase/server";
import ActivityCategoryOptions from "@/app/search/filters/activity-category/activity-category-options";
import { ACTIVITY_CATEGORY_PATH } from "../url-search-params";

export default async function ActivityCategoryFilter({ initialUrlSearchParams}: { initialUrlSearchParams: URLSearchParams }) {
  const activityCategoryPath = initialUrlSearchParams.get(ACTIVITY_CATEGORY_PATH);

  const client = await createSupabaseSSRClient();
  const activityCategories = await client
    .from("activity_category_used")
    .select();

  return (
    <ActivityCategoryOptions
      options={[
        {
          label: "Missing",
          value: null,
          humanReadableValue: "Missing",
          className: "bg-orange-200",
        },
        ...(activityCategories.data?.map(({ code, path, name }) => ({
          label: `${code} ${name}`,
          value: path as string,
          humanReadableValue: `${code} ${name}`,
        })) ?? []),
      ]}
      selected={
        activityCategoryPath
          ?.split(",")
          .map((value) => (value === "null" ? null : value)) ?? []
      }
    />
  );
}
