import { getServerClient } from "@/context/ClientStore";
import ActivityCategoryOptions from "@/app/search/filters/activity-category/activity-category-options";

export default async function ActivityCategoryFilter() {
  const client = await getServerClient();
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
    />
  );
}
