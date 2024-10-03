import { createClient } from "@/utils/supabase/server";
import ActivityCategoryOptions from "@/app/search/filters/activity-category/activity-category-options";

export default async function ActivityCategoryFilter({
  urlSearchParam,
}: {
  readonly urlSearchParam: string | null;
}) {
  const client = createClient();
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
        urlSearchParam
          ?.split(",")
          .map((value) => (value === "null" ? null : value)) ?? []
      }
    />
  );
}
