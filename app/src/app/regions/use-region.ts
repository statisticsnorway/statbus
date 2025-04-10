import { createPostgRESTBrowserClient } from "@/utils/auth/postgrest-client-browser";
import { useState } from "react";
import useSWR, { Fetcher } from "swr";

type Pagination = {
  pageSize: number;
  pageNumber: number;
}
type Queries = {
  name: string;
  code: string;
}
type SearchState = {
  pagination: Pagination;
  queries: Queries
}

const fetcher: Fetcher<RegionResult, SearchState> = async ({pagination, queries}: SearchState) =>
  {
    const client = await createPostgRESTBrowserClient();
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

      const {data: maybeRegions, count: maybeCount} = await query;
      const regions = maybeRegions ?? [];
      const count = maybeCount ?? 0;

    return {regions, count};
}

export default function useRegion() {
  const [pagination, setPagination] = useState({ pageSize: 10, pageNumber: 1 } as Pagination);
  const [queries, setQueries] = useState({ name: "", code: "" } as Queries);

  const { data, isLoading } = useSWR<RegionResult>(
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
    pagination,
    setPagination,
    queries,
    setQueries,
  };
}
