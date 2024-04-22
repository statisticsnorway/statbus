"use client";
import { ReactNode, useMemo, useReducer } from "react";
import { RegionContext, RegionContextState } from "./region-context";
import { regionReducer } from "./region-reducer";
import useRegion from "./use-region";
import useUpdatedUrlSearchParams from "./use-updated-url-params";

interface RegionProviderProps {
  readonly children: ReactNode;
  readonly order: RegionOrder;
  readonly pagination: RegionPagination;
}

export const RegionProvider = ({
  children,
  order: initialOrder,
  pagination,
}: RegionProviderProps) => {
  const [regions, dispatch] = useReducer(regionReducer, {
    order: initialOrder,
    pagination,
    queries: {},
    values: {},
  });

  const {
    regions: { data: regionsResult, isLoading },
    searchParams,
  } = useRegion(regions);

  const ctx: RegionContextState = useMemo(
    () => ({
      regions,
      regionsResult,
      searchParams,
      dispatch,
      isLoading,
    }),
    [regions, regionsResult, searchParams, dispatch, isLoading]
  );
  useUpdatedUrlSearchParams(ctx);
  return (
    <RegionContext.Provider value={ctx}>{children}</RegionContext.Provider>
  );
};
