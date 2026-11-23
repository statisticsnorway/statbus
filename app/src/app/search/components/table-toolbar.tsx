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
import { ResetFilterButton } from "@/app/search/components/reset-filter-button";
import { FilterWrapper } from "./filter-wrapper";
import DataSourceFilter from "../filters/data-source/data-source-filter";
import { ColumnSelectorButton } from "./column-selector-button";
import StatusFilter from "../filters/status/status-filter";
import UnitSizeFilter from "../filters/unit-size/unit-size-filter";
import LastEditByUserFilter from "../filters/last-edit-by-user/last-edit-by-user-filter";
import DomesticFilter from "../filters/domestic-filter";
import CountryFilter from "../filters/country-filter";
import QualityFilter from "../filters/quality-filter";
import {
  ACTIVITY_CATEGORY_PATH,
  DATA_SOURCE,
  DOMESTIC,
  LAST_EDIT_BY_USER,
  LEGAL_FORM,
  PHYSICAL_LOCATION,
  REGION,
  SECTOR,
  STATUS,
  UNIT_SIZE,
} from "../filters/url-search-params";

export default function TableToolbar() {
  return (
    <div className="flex flex-wrap items-center gap-2 mb-4 p-1 lg:p-0 w-full">
      <FilterWrapper columnCode="name">
        <FullTextSearchFilter />
        <ExternalIdentFilter />
      </FilterWrapper>
      <UnitTypeFilter />
      <QualityFilter />
      <FilterWrapper
        columnCode="activity"
        filterKeys={[ACTIVITY_CATEGORY_PATH]}
      >
        <ActivityCategoryFilter />
      </FilterWrapper>
      <FilterWrapper columnCode="region" filterKeys={[REGION]}>
        <RegionFilter />
      </FilterWrapper>
      <FilterWrapper columnCode="sector" filterKeys={[SECTOR]}>
        <SectorFilter />
      </FilterWrapper>
      <FilterWrapper columnCode="legal_form" filterKeys={[LEGAL_FORM]}>
        <LegalFormFilter />
      </FilterWrapper>
      <FilterWrapper columnCode="domestic" filterKeys={[DOMESTIC]}>
        <DomesticFilter />
      </FilterWrapper>
      {/* Always shown, as Unit Type and Quality are: the Regions map's View and download sets it. */}
      <CountryFilter />
      <FilterWrapper columnCode="status">
        <StatusFilter />
      </FilterWrapper>
      <FilterWrapper columnCode="unit_size" filterKeys={[UNIT_SIZE]}>
        <UnitSizeFilter />
      </FilterWrapper>
      <FilterWrapper columnCode="data_sources" filterKeys={[DATA_SOURCE]}>
        <DataSourceFilter />
      </FilterWrapper>
      <FilterWrapper columnCode="last_edit" filterKeys={[LAST_EDIT_BY_USER]}>
        <LastEditByUserFilter />
      </FilterWrapper>
      <StatisticalVariablesFilter />
      <ResetFilterButton />
      <ColumnSelectorButton />
    </div>
  );
}
