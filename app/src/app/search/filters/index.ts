import { createFullTextSearchFilter } from "@/app/search/filters/full-text-search-filter";
import { createUnitTypeSearchFilter } from "@/app/search/filters/unit-type-search-filter";
import { createTaxRegIdentFilter } from "@/app/search/filters/tax-reg-ident-filter";
import { createRegionFilter } from "@/app/search/filters/region-filter";
import { createSectorFilter } from "@/app/search/filters/sector-filter";
import { creatLegalFormFilter } from "@/app/search/filters/legal-form-filter";
import { createActivityCategoryFilter } from "@/app/search/filters/activity-category-filter";
import { createStatisticalVariableFilters } from "@/app/search/filters/statistical-variable-filters";
import { createInvalidCodesFilter } from "@/app/search/filters/invalid-codes-filter";

export function createFilters(
  opts: FilterOptions,
  params: URLSearchParams
): SearchFilter[] {
  return [
    createFullTextSearchFilter(params),
    createTaxRegIdentFilter(params),
    createUnitTypeSearchFilter(params),
    createRegionFilter(params, opts.regions),
    createSectorFilter(params, opts.sectors),
    creatLegalFormFilter(params, opts.legalForms),
    createActivityCategoryFilter(params, opts.activityCategories),
    createInvalidCodesFilter(params),
    ...createStatisticalVariableFilters(params, opts.statisticalVariables),
  ];
}
