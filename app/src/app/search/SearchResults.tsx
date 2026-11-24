"use client";

import { ReactNode } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useSetAtom, useAtomValue, useAtom } from 'jotai';
import { derivedApiSearchParamsAtom, performSearchAtom, fetchSearchPageDataAtom, searchPageDataReadyAtom, paginationAtom, type SearchPagination, sortingAtom, SearchSorting, queryAtom, filtersAtom } from '@/atoms/search';
import { searchStateInitializedAtom } from "@/atoms/app";
import { externalIdentTypesAtom, statDefinitionsAtom } from "@/atoms/base-data";
import type { Tables } from "@/lib/database.types";
import { useSearchUrlSync } from "./hooks/useSearchUrlSync";
import { deriveStateFromUrl } from "./derive-state-from-url";

interface SearchResultsProps {
  readonly children: ReactNode;
  readonly allRegions: Tables<"region_used">[];
  readonly allActivityCategories: Tables<"activity_category_used">[];
  readonly allStatuses: Tables<"status">[];
  readonly allUnitSizes: Tables<"unit_size">[];
  readonly allDataSources: Tables<"data_source_used">[];
  readonly allExternalIdentTypes: Tables<"external_ident_type_enabled">[];
  readonly allLegalForms: Tables<"legal_form_used">[];
  readonly allSectors: Tables<"sector_used">[];
  readonly initialUrlSearchParamsString: string;
}

export function SearchResults({
  children,
  allRegions,
  allActivityCategories,
  allStatuses,
  allUnitSizes,
  allDataSources,
  allExternalIdentTypes,
  allLegalForms,
  allSectors,
  initialUrlSearchParamsString,
}: SearchResultsProps) {
  const setFilters = useSetAtom(filtersAtom);
  const setQuery = useSetAtom(queryAtom);
  const [pagination, setPagination] = useAtom(paginationAtom); // Get setter for new atom
  const [sorting, setSorting] = useAtom(sortingAtom);
  const [isInitialized, setInitialized] = useAtom(searchStateInitializedAtom);
  const fetchSearchPageData = useSetAtom(fetchSearchPageDataAtom);
  const searchPageDataReady = useAtomValue(searchPageDataReadyAtom);
  const externalIdentTypes = useAtomValue(externalIdentTypesAtom);
  const statDefinitions = useAtomValue(statDefinitionsAtom);

  // Effect 1: Fetch lookup data client-side
  // This avoids RSC hydration timing issues by fetching directly from the API.
  // The fetch is triggered once when the component mounts or when data needs refresh.
  useGuardedEffect(() => {
    if (searchPageDataReady) {
      return; // Data already loaded
    }
    fetchSearchPageData();
  }, [searchPageDataReady, fetchSearchPageData], 'SearchResults:fetchLookupData');

  // Effect 2: One-time URL initialization (guarded by isInitialized)
  // This only runs once to parse URL params into state, avoiding overwrites on navigation.
  useGuardedEffect(() => {
    if (isInitialized) {
      return;
    }

    const initialUrlSearchParams = new URLSearchParams(initialUrlSearchParamsString);
    const { _initialPagination, _initialSorting, _initialQuery, _initialFilters } =
      deriveStateFromUrl(initialUrlSearchParams, externalIdentTypes, statDefinitions);

    setQuery(_initialQuery);
    setFilters(_initialFilters);
    setSorting(_initialSorting);
    setPagination(_initialPagination);
    setInitialized(true);
  }, [
    isInitialized,
    setInitialized,
    initialUrlSearchParamsString,
    externalIdentTypes,
    statDefinitions,
    setQuery,
    setFilters,
    setPagination,
    setSorting,
  ], 'SearchResults:initializeFromUrl');

  useSearchUrlSync();

  const derivedApiParamsFromJotai = useAtomValue(derivedApiSearchParamsAtom);
  const performSearch = useSetAtom(performSearchAtom);
  
  // This effect remains to trigger the data fetch whenever the API params change.
  useGuardedEffect(() => {
    if (isInitialized && derivedApiParamsFromJotai.toString()) {
      performSearch();
    }
  }, [isInitialized, derivedApiParamsFromJotai, performSearch], 'SearchResults:directFetch');

  return (
    <>
      {children}
    </>
  );
}
