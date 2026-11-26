import { getBrowserRestClient } from "@/context/RestClientStore";
import { useState } from "react";
import useSWR, { Fetcher } from "swr";

type Pagination = {
  pageSize: number;
  pageNumber: number;
}
type Queries = {
  name: string;
  code: string;
  /** Regions with a centre point, without one, or both (""): a list filter (owner 2026-11-23, z2qt08). */
  coordinates: "" | "with" | "without";
}
type SearchState = {
  pagination: Pagination;
  queries: Queries
}

const fetcher: Fetcher<RegionResult, SearchState> = async ({pagination, queries}: SearchState) =>
  {
    const client = await getBrowserRestClient();
    let query = client
      .from('region')
      .select('*', {count: 'exact'})
      .order('path',{ ascending: true});

      const offset = pagination.pageNumber && pagination.pageSize
        ? (pagination.pageNumber - 1) * pagination.pageSize
        : 0;
      const limit = pagination.pageSize || 10;
      query = query.range(offset, offset + limit - 1);

      if (queries.name) query = query.ilike('name', `%${queries.name}%`);
      if (queries.code) query = query.like('code', `${queries.code}%`);
      if (queries.coordinates === 'with') query = query.not('latitude', 'is', null);
      if (queries.coordinates === 'without') query = query.is('latitude', null);

      const {data: maybeRegions, count: maybeCount} = await query;
      const regions = maybeRegions ?? [];
      const count = maybeCount ?? 0;

    return {regions, count};
}

export default function useRegion() {
  const [pagination, setPagination] = useState({ pageSize: 10, pageNumber: 1 } as Pagination);
  const [queries, setQueries] = useState({ name: "", code: "", coordinates: "" } as Queries);

  const { data, isLoading, mutate } = useSWR<RegionResult>(
    `regions?${JSON.stringify(pagination)}${JSON.stringify(queries)}`,
    (key) => fetcher({pagination, queries}),
    {
      keepPreviousData: true,
      revalidateOnFocus: false,
    }
  );

  return {
    data,
    isLoading,
    /** Reloads the shown page, after a region's centre is saved. */
    refresh: () => mutate(),
    pagination,
    setPagination,
    queries,
    setQueries,
  };
}
