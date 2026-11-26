import { DrillDownPoint } from "@/app/reports/types/drill-down";
import { Button } from "@/components/ui/button";
import Link from "next/link";
import { List as ListIcon, Map as MapIcon } from "lucide-react";
import {
  ACTIVITY_CATEGORY_PATH,
  REGION,
  UNIT_TYPE,
} from "@/app/search/filters/url-search-params";

/**
 * Opens the drilldown's units in the search: as the list ("View and download") or as the search's
 * map (5nq78t, owner 2026-11-26). Both are the same search, so the drilldown hands over its region,
 * activity and unit type once and the search keeps list and map in step.
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
      <Button asChild variant="outline">
        <Link href={`/search/map${query}`} data-drilldown-map-link="">
          <MapIcon className="mr-1.5 h-4 w-4" />
          Show on map
        </Link>
      </Button>
      <Button asChild>
        <Link href={`/search${query}`}>
          <ListIcon className="mr-1.5 h-4 w-4" />
          View and download
        </Link>
      </Button>
    </div>
  );
};
