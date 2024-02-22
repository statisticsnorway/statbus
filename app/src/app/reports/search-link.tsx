import {DrillDownPoint} from "@/app/reports/types/drill-down";
import {Button} from "@/components/ui/button";
import Link from "next/link";
import {SearchFilterName} from "@/app/search/search.types";

export const SearchLink = ({region, activityCategory}: {
  readonly region: DrillDownPoint | null,
  readonly activityCategory: DrillDownPoint | null
}) => {

  const searchParams = new URLSearchParams();

  if (region) {
    const name: SearchFilterName = 'physical_region_path'
    searchParams.set(name, region.path);
  }

  if (activityCategory) {
    const name: SearchFilterName = 'primary_activity_category_path'
    searchParams.set(name, activityCategory.path);
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
