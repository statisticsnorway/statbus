import { Tables } from "@/lib/database.types";
import { createSupabaseBrowserClientAsync } from "@/utils/supabase/client";
import { useState } from "react";
import useSWR, { Fetcher } from "swr";

type Pagination = {
  pageSize: number;
  pageNumber: number;
};

type Queries = {
  name: string;
  code: string;
};

type ActivityCategoryResult = {
  activityCategories: Tables<"region">[];
  count: number;
};

const fetcher: Fetcher<ActivityCategoryResult, { pagination: Pagination; queries: Queries }> = async ({ pagination, queries }) => {
  const client = await createSupabaseBrowserClientAsync();
  let query = client.from('activity_category').select('*', { count: 'exact' });

  const offset = pagination.pageNumber && pagination.pageSize
    ? (pagination.pageNumber - 1) * pagination.pageSize
    : 0;
  const limit = pagination.pageSize || 10;
  query = query.range(offset, offset + limit - 1);

  if (queries.name) query = query.ilike('name', `%${queries.name}%`);
  if (queries.code) query = query.like('code', `${queries.code}%`);

  const { data: maybeActivityCategories, count: maybeCount } = await query;
  const activityCategories = maybeActivityCategories ?? [];
  const count = maybeCount ?? 0;

  return { activityCategories, count };
};
export default function useActivityCategories() {
  const [pagination, setPagination] = useState({ pageSize: 10, pageNumber: 1 } as Pagination);
  const [queries, setQueries] = useState({ name: "", code: "" } as Queries);

  const { data, isLoading } = useSWR<ActivityCategoryResult>(
    `activity-categories?${JSON.stringify(pagination)}${JSON.stringify(queries)}`,
    () => fetcher({ pagination, queries }),
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
