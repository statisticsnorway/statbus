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
import PhysicalLocationFilter from "../filters/physical-location-filter";
import CountryFilter from "../filters/country-filter";
import QualityFilter from "../filters/quality-filter";
import {
  ACTIVITY_CATEGORY_PATH,
  DATA_SOURCE,
  DOMESTIC,
  LAST_EDIT_BY_USER,
  LEGAL_FORM,
  PHYSICAL_LOCATION,
  PHYSICAL_COUNTRY,
  REGION,
  SECTOR,
  STATUS,
  UNIT_SIZE,
} from "../filters/url-search-params";

/**
 * How a filter in effect stands out from the ones not in use (owner 2026-11-27, look A of three
 * tried): a solid dark border and a bold title on its button, and its value badges dark with white
 * medium-weight text, heavy enough to read on the dark fill. Every filter button marks itself with
 * data-filter-active while it has a value (OptionsFilter, ConditionalFilter, ExternalIdentFilter);
 * this toolbar styles what the marker names, so the look is defined once. Quality's orange badge
 * keeps its colour, which marks a quality finding.
 */
const ACTIVE_FILTER_LOOK = [
  "[&_[data-filter-active]]:border-solid",
  "[&_[data-filter-active]]:border-gray-700",
  "[&_[data-filter-active]]:font-semibold",
  "[&_[data-filter-active]_[data-slot=badge]:not([class*=bg-orange])]:bg-gray-700",
  "[&_[data-filter-active]_[data-slot=badge]:not([class*=bg-orange])]:text-white",
  "[&_[data-filter-active]_[data-slot=badge]:not([class*=bg-orange])]:font-medium",
].join(" ");

export default function TableToolbar() {
  return (
    <div
      className={`flex flex-wrap items-center gap-2 mb-4 p-1 lg:p-0 w-full ${ACTIVE_FILTER_LOOK}`}
    >
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
      <FilterWrapper
        columnCode="physical_address"
        filterKeys={[PHYSICAL_LOCATION]}
      >
        <PhysicalLocationFilter />
      </FilterWrapper>
      <FilterWrapper
        columnCode="physical_country_iso_2"
        filterKeys={[PHYSICAL_COUNTRY]}
      >
        <CountryFilter />
      </FilterWrapper>
      <FilterWrapper columnCode="status" filterKeys={[STATUS]}>
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
