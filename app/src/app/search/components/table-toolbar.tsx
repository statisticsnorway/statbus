import FullTextSearchFilter from "@/app/search/filters/full-text-search-filter";
import {
  ACTIVITY_CATEGORY_PATH,
  INVALID_CODES,
  LEGAL_FORM,
  REGION,
  SEARCH,
  SECTOR,
  TAX_REG_IDENT,
  UNIT_TYPE,
} from "@/app/search/filters/url-search-params";
import TaxRegIdentFilter from "@/app/search/filters/tax-reg-ident-filter";
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

interface ITableToolbarProps {
  urlSearchParams: URLSearchParams;
}

export default function TableToolbar({ urlSearchParams }: ITableToolbarProps) {
  const search = urlSearchParams.get(SEARCH);
  const taxRegIdent = urlSearchParams.get(TAX_REG_IDENT);
  const unitType = urlSearchParams.get(UNIT_TYPE);
  const sector = urlSearchParams.get(SECTOR);
  const region = urlSearchParams.get(REGION);
  const legalForm = urlSearchParams.get(LEGAL_FORM);
  const activityCategoryPath = urlSearchParams.get(ACTIVITY_CATEGORY_PATH);
  const invalidCodes = urlSearchParams.get(INVALID_CODES);
  return (
    <div className="flex flex-wrap items-center p-1 lg:p-0 [&>*]:mb-2 [&>*]:mx-1 w-screen lg:w-full">
      <FullTextSearchFilter urlSearchParam={search} />
      <TaxRegIdentFilter urlSearchParam={taxRegIdent} />
      <UnitTypeFilter urlSearchParam={unitType} />
      <Suspense fallback={<FilterSkeleton title="Sector" />}>
        <SectorFilter urlSearchParam={sector} />
      </Suspense>
      <Suspense fallback={<FilterSkeleton title="Region" />}>
        <RegionFilter urlSearchParam={region} />
      </Suspense>
      <Suspense fallback={<FilterSkeleton title="Legal Form" />}>
        <LegalFormFilter urlSearchParam={legalForm} />
      </Suspense>
      <Suspense fallback={<FilterSkeleton title="Activity Category" />}>
        <ActivityCategoryFilter urlSearchParam={activityCategoryPath} />
      </Suspense>
      <StatisticalVariablesFilter urlSearchParams={urlSearchParams} />
      <InvalidCodesFilter urlSearchParam={invalidCodes} />
      <ResetFilterButton />
    </div>
  );
}
