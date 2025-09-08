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
import DataSourceFilter from "../filters/data-source/data-source-filter";
import { ColumnSelectorButton } from "./column-selector-button";
import StatusFilter from "../filters/status/status-filter";
import UnitSizeFilter from "../filters/unit-size/unit-size-filter";

export default function TableToolbar() {
  return (
    <div className="flex flex-wrap items-center gap-2 mb-4 p-1 lg:p-0 w-full">
      <FilterWrapper columnCode="name">
        <FullTextSearchFilter />
        <ExternalIdentFilter />
      </FilterWrapper>
      <UnitTypeFilter />
      <FilterWrapper columnCode="sector">
        <SectorFilter />
      </FilterWrapper>
      <FilterWrapper columnCode="region">
        <RegionFilter />
      </FilterWrapper>
      <FilterWrapper columnCode="legal_form">
        <LegalFormFilter />
      </FilterWrapper>
      <FilterWrapper columnCode="activity">
        <ActivityCategoryFilter />
      </FilterWrapper>
      <FilterWrapper columnCode="status">
        <StatusFilter />
      </FilterWrapper>
      <FilterWrapper columnCode="unit_size">
        <UnitSizeFilter />
      </FilterWrapper>
      <FilterWrapper columnCode="data_sources">
        <DataSourceFilter />
      </FilterWrapper>
      <StatisticalVariablesFilter />
      <InvalidCodesFilter />
      <ResetFilterButton />
      <ColumnSelectorButton />
    </div>
  );
}
