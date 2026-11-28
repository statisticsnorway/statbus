import { DrillDownPoint } from "@/app/reports/types/drill-down";
import { Button } from "@/components/ui/button";
import Link from "next/link";
import { List as ListIcon } from "lucide-react";
import {
  ACTIVITY_CATEGORY_PATH,
  REGION,
  UNIT_TYPE,
} from "@/app/search/filters/url-search-params";

/**
 * Opens the drilldown's units in the search's list ("View and download"): the drilldown hands over
 * its region, activity and unit type. The map of them is the region panel's own Map view
 * (ppvxg2, owner 2026-11-28 14:25), so no link to the search's map is offered here.
 */
export const SearchLink = ({
  region,
  activityCategory,
  unitType,
}: {
  readonly region: DrillDownPoint | null;
  readonly activityCategory: DrillDownPoint | null;
  readonly unitType: UnitType;
}) => {
  const searchParams = new URLSearchParams();

  if (region) {
    searchParams.set(REGION, region.path);
  }

  if (activityCategory) {
    searchParams.set(ACTIVITY_CATEGORY_PATH, activityCategory.path);
  }

  searchParams.set(UNIT_TYPE, unitType);

  const query = searchParams.size ? `?${searchParams}` : "";
  return (
    <div className="flex gap-2">
      <Button asChild>
        <Link href={`/search${query}`}>
          <ListIcon className="mr-1.5 h-4 w-4" />
          View and download
        </Link>
      </Button>
    </div>
  );
};
