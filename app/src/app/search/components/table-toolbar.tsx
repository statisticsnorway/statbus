import FullTextSearchFilter from "@/app/search/filtersV2/full-text-search-filter";
import {
  ACTIVITY_CATEGORY_PATH,
  INVALID_CODES,
  LEGAL_FORM,
  REGION,
  SEARCH,
  SECTOR,
  TAX_REG_IDENT,
  UNIT_TYPE,
} from "@/app/search/filtersV2/url-search-params";
import TaxRegIdentFilter from "@/app/search/filtersV2/tax-reg-ident-filter";
import UnitTypeFilter from "@/app/search/filtersV2/unit-type-filter";
import { Suspense } from "react";
import { FilterSkeleton } from "@/app/search/filter-skeleton";
import SectorFilter from "@/app/search/filtersV2/sector/sector-filter";
import RegionFilter from "@/app/search/filtersV2/region/region-filter";
import LegalFormFilter from "@/app/search/filtersV2/legal-form/legal-form-filter";
import ActivityCategoryFilter from "@/app/search/filtersV2/activity-category/activity-category-filter";
import StatisticalVariablesFilter from "@/app/search/filtersV2/statistical-variables/statistical-variables-filter";
import InvalidCodesFilter from "@/app/search/filtersV2/invalid-codes-filter";
import { ResetFilterButton } from "@/app/search/components/reset-filter-button";

interface ITableToolbarProps {
  urlSearchParams: URLSearchParams;
}

export default function TableToolbar({ urlSearchParams }: ITableToolbarProps) {
  return (
    <div className="flex flex-wrap items-center p-1 lg:p-0 [&>*]:mb-2 [&>*]:mx-1 w-screen lg:w-full">
      <FullTextSearchFilter urlSearchParam={urlSearchParams.get(SEARCH)} />
      <TaxRegIdentFilter urlSearchParam={urlSearchParams.get(TAX_REG_IDENT)} />
      <UnitTypeFilter urlSearchParam={urlSearchParams.get(UNIT_TYPE)} />
      <Suspense fallback={<FilterSkeleton title="Sector" />}>
        <SectorFilter urlSearchParam={urlSearchParams.get(SECTOR)} />
      </Suspense>
      <Suspense fallback={<FilterSkeleton title="Region" />}>
        <RegionFilter urlSearchParam={urlSearchParams.get(REGION)} />
      </Suspense>
      <Suspense fallback={<FilterSkeleton title="Legal Form" />}>
        <LegalFormFilter urlSearchParam={urlSearchParams.get(LEGAL_FORM)} />
      </Suspense>
      <Suspense fallback={<FilterSkeleton title="Activity Category" />}>
        <ActivityCategoryFilter
          urlSearchParam={urlSearchParams.get(ACTIVITY_CATEGORY_PATH)}
        />
      </Suspense>
      <StatisticalVariablesFilter urlSearchParams={urlSearchParams} />
      <InvalidCodesFilter urlSearchParam={urlSearchParams.get(INVALID_CODES)} />
      <ResetFilterButton />
    </div>
  );
}
