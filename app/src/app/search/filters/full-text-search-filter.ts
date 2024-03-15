import { createURLParamsResolver } from "@/app/search/filters/url-params-resolver";

export const SEARCH: SearchFilterName = "search";

export const createFullTextSearchFilter = (
  params: URLSearchParams
): SearchFilter => {
  const [search] = createURLParamsResolver(params)(SEARCH);
  return {
    type: "search",
    label: "Name",
    name: SEARCH,
    operator: "fts",
    selected: search ? [search] : [],
  };
};
