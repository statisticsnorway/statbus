export const dynamic = "force-dynamic";

import { Metadata } from "next";
import {
  toURLSearchParams,
  URLSearchParamsDict,
} from "@/lib/url-search-params-dict";
import SearchMapPageClient from "./SearchMapPageClient";

export const metadata: Metadata = {
  title: "Search statistical units: map",
};

/**
 * The search's map view (5nq78t): the same search as /search, shown by region. The lookups the
 * filters need are fetched client-side, as the list does (fetchSearchPageDataAtom).
 */
export default async function SearchMapPage(props: {
  searchParams: Promise<URLSearchParamsDict>;
}) {
  const initial = toURLSearchParams(await props.searchParams);
  initial.sort();
  return (
    <SearchMapPageClient initialUrlSearchParamsString={initial.toString()} />
  );
}
