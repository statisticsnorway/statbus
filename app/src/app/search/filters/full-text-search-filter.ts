export const SEARCH: SearchFilterName = "search";

export const createFullTextSearchFilter = (
  params: URLSearchParams
): SearchFilter => {
  const search = params.get(SEARCH);
  return {
    type: "search",
    label: "Name",
    name: SEARCH,
    selected: search ? [search] : [],
  };
};
