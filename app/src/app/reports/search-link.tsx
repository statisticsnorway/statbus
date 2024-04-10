import { DrillDownPoint } from "@/app/reports/types/drill-down";
import { Button } from "@/components/ui/button";
import Link from "next/link";
import {
  ACTIVITY_CATEGORY_PATH,
  REGION,
  UNIT_TYPE,
} from "@/app/search/filters/url-search-params";

export const SearchLink = ({
  region,
  activityCategory,
}: {
  readonly region: DrillDownPoint | null;
  readonly activityCategory: DrillDownPoint | null;
}) => {
  const searchParams = new URLSearchParams();

  if (region) {
    searchParams.set(REGION, region.path);
  }

  if (activityCategory) {
    searchParams.set(ACTIVITY_CATEGORY_PATH, activityCategory.path);
  }

  searchParams.set(UNIT_TYPE, "enterprise,legal_unit,establishment");

  return (
    <Button asChild>
      <Link href={searchParams.size ? `/search?${searchParams}` : "/search"}>
        View and export statistical units
      </Link>
    </Button>
  );
};
