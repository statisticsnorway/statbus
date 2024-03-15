import { Tables } from "@/lib/database.types";
import { createURLParamsResolver } from "@/app/search/filters/url-params-resolver";

export const ACTIVITY_CATEGORY: SearchFilterName =
  "primary_activity_category_path";

export const createActivityCategoryFilter = (
  params: URLSearchParams,
  activityCategories: Tables<"activity_category_used">[]
): SearchFilter => {
  const [activityCategory] = createURLParamsResolver(params)(ACTIVITY_CATEGORY);
  return {
    type: "radio",
    name: ACTIVITY_CATEGORY,
    label: "Activity Category",
    options: [
      {
        label: "Missing",
        value: null,
        humanReadableValue: "Missing",
        className: "bg-orange-200",
      },
      ...activityCategories.map(({ code, path, name }) => ({
        label: `${code} ${name}`,
        value: path as string,
        humanReadableValue: `${code} ${name}`,
      })),
    ],
    selected: activityCategory
      ? [activityCategory === "null" ? null : activityCategory]
      : [],
  };
};
