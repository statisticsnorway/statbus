import { createClient } from "@/lib/supabase/server";
import ActivityCategoryOptions from "@/app/search/filtersV2/activity-category/activity-category-options";

export default async function ActivityCategoryFilter() {
  const client = createClient();
  const activityCategories = await client
    .from("activity_category_used")
    .select();

  await new Promise((resolve) => setTimeout(resolve, 1500));

  // TODO: remove demo delay
  // TODO: pass url search params to Child Component

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
      selected={[]}
    />
  );
}
