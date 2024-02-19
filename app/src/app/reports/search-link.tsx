import {DrillDownPoint} from "@/app/reports/types/drill-down";
import {Button} from "@/components/ui/button";
import Link from "next/link";
import {PHYSICAL_REGION_PATH, PRIMARY_ACTIVITY_CATEGORY_PATH} from "@/app/search/constants";

export const SearchLink = ({region, activityCategory}: {
  readonly region: DrillDownPoint | null,
  readonly activityCategory: DrillDownPoint | null
}) => {

  const searchParams = new URLSearchParams();

  if (region) {
    searchParams.set(PHYSICAL_REGION_PATH, region.path);
  }

  if (activityCategory) {
    searchParams.set(PRIMARY_ACTIVITY_CATEGORY_PATH, activityCategory.path);
  }

  return (
    <Button asChild>
      <Link
        href={searchParams.size ? `/search?${searchParams}` : '/search'}>
        View and export statistical units
      </Link>
    </Button>
  )
}
