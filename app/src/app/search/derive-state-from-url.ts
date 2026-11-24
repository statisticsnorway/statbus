import type { Tables } from "@/lib/database.types";
import type { SearchPagination, SearchSorting } from "@/atoms/search";
import {
  SEARCH,
  activityCategoryDeriveStateUpdateFromSearchParams,
  dataSourceDeriveStateUpdateFromSearchParams,
  externalIdentDeriveStateUpdateFromSearchParams,
  fullTextSearchDeriveStateUpdateFromSearchParams,
  legalFormDeriveStateUpdateFromSearchParams,
  regionDeriveStateUpdateFromSearchParams,
  sectorDeriveStateUpdateFromSearchParams,
  statusDeriveStateUpdateFromSearchParams,
  domesticDeriveStateUpdateFromSearchParams,
  physicalLocationDeriveStateUpdateFromSearchParams,
  physicalCountryDeriveStateUpdateFromSearchParams,
  lastEditByUserDeriveStateUpdateFromSearchParams,
  qualityDeriveStateUpdateFromSearchParams,
  statisticalVariablesDeriveStateUpdateFromSearchParams,
  unitSizeDeriveStateUpdateFromSearchParams,
  unitTypeDeriveStateUpdateFromSearchParams,
} from "./filters/url-search-params";
import { SearchAction } from "./search.d";

/**
 * The search state a URL describes: its text query, filters, sorting and page. A pure function,
 * the one URL -> state conversion, used by the search page and by the Reports map (5nq78t), which
 * reads a search from its URL without becoming the search page.
 */
export const deriveStateFromUrl = (
  urlSearchParams: URLSearchParams,
  externalIdentTypes: Tables<"external_ident_type_enabled">[],
  statDefinitions: Tables<"stat_definition_enabled">[]
): {
  _initialQuery: string;
  _initialFilters: Record<string, unknown>;
  _initialPagination: SearchPagination;
  _initialSorting: SearchSorting;
} => {
  const ftsAction =
    fullTextSearchDeriveStateUpdateFromSearchParams(urlSearchParams);
  const unitTypeAction =
    unitTypeDeriveStateUpdateFromSearchParams(urlSearchParams);
  const legalFormAction =
    legalFormDeriveStateUpdateFromSearchParams(urlSearchParams);
  const regionAction = regionDeriveStateUpdateFromSearchParams(urlSearchParams);
  const sectorAction = sectorDeriveStateUpdateFromSearchParams(urlSearchParams);
  const activityCategoryAction =
    activityCategoryDeriveStateUpdateFromSearchParams(urlSearchParams);
  const statusAction = statusDeriveStateUpdateFromSearchParams(urlSearchParams);
  const domesticAction =
    domesticDeriveStateUpdateFromSearchParams(urlSearchParams);
  const physicalLocationAction =
    physicalLocationDeriveStateUpdateFromSearchParams(urlSearchParams);
  const physicalCountryAction =
    physicalCountryDeriveStateUpdateFromSearchParams(urlSearchParams);
  const lastEditByUserAction =
    lastEditByUserDeriveStateUpdateFromSearchParams(urlSearchParams);
  const unitSizeAction =
    unitSizeDeriveStateUpdateFromSearchParams(urlSearchParams);
  const dataSourceAction =
    dataSourceDeriveStateUpdateFromSearchParams(urlSearchParams);
  const qualityAction =
    qualityDeriveStateUpdateFromSearchParams(urlSearchParams);
  const externalIdentActions = externalIdentTypes.map((extType) =>
    externalIdentDeriveStateUpdateFromSearchParams(extType, urlSearchParams)
  );
  const statVarActions = statisticalVariablesDeriveStateUpdateFromSearchParams(
    statDefinitions,
    urlSearchParams
  );

  const allActions = [
    ftsAction,
    unitTypeAction,
    legalFormAction,
    regionAction,
    sectorAction,
    activityCategoryAction,
    statusAction,
    domesticAction,
    physicalLocationAction,
    physicalCountryAction,
    lastEditByUserAction,
    unitSizeAction,
    dataSourceAction,
    qualityAction,
    ...externalIdentActions,
    ...statVarActions,
  ].filter(Boolean) as SearchAction[];

  let newInitialQuery = "";
  const newInitialFilters: Record<string, unknown> = {};

  allActions.forEach((action) => {
    if (action.type === "set_query") {
      const { app_param_name, app_param_values } = action.payload;
      if (app_param_name === SEARCH) {
        // This is the definitive fix. By trimming the query here, we make the
        // URL parsing logic symmetrical with the URL serialization logic, which
        // also trims the query. This prevents the infinite loop.
        newInitialQuery = (app_param_values[0] || "").trim();
      } else {
        const isExternalIdent = externalIdentTypes.some(
          (et) => et.code === app_param_name
        );
        const isStatVar = statDefinitions.some(
          (sd) => sd.code === app_param_name
        );

        if (isExternalIdent) {
          const value = app_param_values[0];
          // Only set the filter if the value is a non-empty string.
          // This prevents `?orgnr=` from creating `{ orgnr: "" }` in the state.
          if (value) {
            newInitialFilters[app_param_name] = value;
          }
        } else if (isStatVar) {
          const val = app_param_values[0];
          // Only set the filter if the value is a non-empty string.
          if (val) {
            newInitialFilters[app_param_name] = val.replace(".", ":");
          }
        } else {
          newInitialFilters[app_param_name] = app_param_values.filter(
            (v) => v !== ""
          );
        }
      }
    }
  });

  let initialOrder: SearchSorting = { field: "name", direction: "asc" };
  const orderParam = urlSearchParams.get("order");
  if (orderParam) {
    const [orderBy, orderDirection] = orderParam.split(".");
    const validOrderDirection =
      orderDirection === "desc.nullslast" ? "desc.nullslast" : "asc";
    initialOrder = {
      field: orderBy,
      direction: validOrderDirection as "asc" | "desc.nullslast",
    };
  }

  const initialPagination = {
    page: Number(urlSearchParams.get("page")) || 1,
    pageSize: 10, // Default page size is now hardcoded here
  };

  // The pagination state is now handled by its own atom and is not returned here.
  // The `initializeState` effect will need to be updated to set it.
  return {
    _initialQuery: newInitialQuery,
    _initialFilters: newInitialFilters,
    _initialSorting: initialOrder,
    _initialPagination: initialPagination,
  };
};
