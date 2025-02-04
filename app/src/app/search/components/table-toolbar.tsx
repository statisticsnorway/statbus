import FullTextSearchFilter from "@/app/search/filters/full-text-search-filter";
import ExternalIdentFilter from "@/app/search/filters/external-ident/external-ident-filter";
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
import { FilterWrapper } from "./filter-wrapper";
import { IURLSearchParamsDict } from "@/lib/url-search-params-dict";
import DataSourceFilter from "../filters/data-source/data-source-filter";
import { ColumnSelectorButton } from "./column-selector-button";
import StatusFilter from "../filters/status/status-filter";

export default function TableToolbar({
  initialUrlSearchParamsDict,
}: IURLSearchParamsDict) {
  return (
    <div className="flex flex-wrap items-center gap-2 mb-4 p-1 lg:p-0 w-full">
      <FilterWrapper columnCode="name">
        <FullTextSearchFilter />
        <ExternalIdentFilter />
      </FilterWrapper>
      <UnitTypeFilter />
      <FilterWrapper columnCode="sector">
        <Suspense fallback={<FilterSkeleton title="Sector" />}>
          <SectorFilter />
        </Suspense>
      </FilterWrapper>
      <FilterWrapper columnCode="region">
        <Suspense fallback={<FilterSkeleton title="Region" />}>
          <RegionFilter />
        </Suspense>
      </FilterWrapper>
      <FilterWrapper columnCode="legal_form">
        <Suspense fallback={<FilterSkeleton title="Legal Form" />}>
          <LegalFormFilter />
        </Suspense>
      </FilterWrapper>
      <FilterWrapper columnCode="activity">
        <Suspense fallback={<FilterSkeleton title="Activity Category" />}>
          <ActivityCategoryFilter />
        </Suspense>
      </FilterWrapper>
      <FilterWrapper columnCode="status">
        <Suspense fallback={<FilterSkeleton title="Status" />}>
          <StatusFilter />
        </Suspense>
      </FilterWrapper>
      <FilterWrapper columnCode="data_sources">
        <Suspense fallback={<FilterSkeleton title="Data Source" />}>
          <DataSourceFilter />
        </Suspense>
      </FilterWrapper>
      <StatisticalVariablesFilter />
      <InvalidCodesFilter />
      <ResetFilterButton />
      <ColumnSelectorButton />
    </div>
  );
}
