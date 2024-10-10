import FullTextSearchFilter from "@/app/search/filters/full-text-search-filter";
import ExternalIdentFilter from "@/app/search/filters/external-ident-filter";
import UnitTypeFilter from "@/app/search/filters/unit-type-filter";
import { Suspense } from "react";
import { FilterSkeleton } from "@/app/search/components/filter-skeleton";
import SectorFilter from "@/app/search/filters/sector/sector-filter";
import RegionFilter from "@/app/search/filters/region/region-filter";
import LegalFormFilter from "@/app/search/filters/legal-form/legal-form-filter";
import ActivityCategoryFilter from "@/app/search/filters/activity-category/activity-category-filter";
import StatisticalVariablesFilter from "@/app/search/filters/statistical-variables/statistical-variables-filter";
import InvalidCodesFilter from "@/app/search/filters/invalid-codes-filter";
import { ResetFilterButton } from "@/app/search/components/reset-filter-button";

export default function TableToolbar({ initialUrlSearchParams}: { initialUrlSearchParams: URLSearchParams }) {
  return (
    <div className="flex flex-wrap items-center p-1 lg:p-0 [&>*]:mb-2 [&>*]:mx-1 w-screen lg:w-full">
      <FullTextSearchFilter initialUrlSearchParams={initialUrlSearchParams} />
      <ExternalIdentFilter initialUrlSearchParams={initialUrlSearchParams} />
      <UnitTypeFilter initialUrlSearchParams={initialUrlSearchParams} />
      <Suspense fallback={<FilterSkeleton title="Sector" />}>
        <SectorFilter initialUrlSearchParams={initialUrlSearchParams} />
      </Suspense>
      <Suspense fallback={<FilterSkeleton title="Region" />}>
        <RegionFilter initialUrlSearchParams={initialUrlSearchParams} />
      </Suspense>
      <Suspense fallback={<FilterSkeleton title="Legal Form" />}>
        <LegalFormFilter initialUrlSearchParams={initialUrlSearchParams} />
      </Suspense>
      <Suspense fallback={<FilterSkeleton title="Activity Category" />}>
        <ActivityCategoryFilter initialUrlSearchParams={initialUrlSearchParams} />
      </Suspense>
      <StatisticalVariablesFilter urlSearchParams={initialUrlSearchParams} />
      <InvalidCodesFilter initialUrlSearchParams={initialUrlSearchParams} />
      <ResetFilterButton />
    </div>
  );
}
