type ActivityCategoryResult = {
  activityCategories: Tables<"activity_category">[];
  count: number;
};
interface ActivityCategoryTableProps {
  activityCategories: Tables<"activity_category">[];
}
interface ActivityCategoryTableRowProps {
  activityCategories: Tables<"activity_category">;
}
