import { useState } from "react";
import useSWR, { Fetcher } from "swr";
const fetcher: Fetcher<ActivityCategoryResult, string> = (...args) =>
  fetch(...args).then((res) => res.json());
export default function useActivityCategories() {
  const [pagination, setPagination] = useState({ pageSize: 10, pageNumber: 1 });
  const [queries, setQueries] = useState({
    name: "",
    code: "",
  });
  const searchParams = new URLSearchParams();
  if (pagination.pageNumber && pagination.pageSize) {
    const offset = (pagination.pageNumber - 1) * pagination.pageSize;
    searchParams.set("offset", offset.toString());
    searchParams.set("limit", pagination.pageSize.toString());
  }
  if (queries.name) searchParams.set("name", `ilike.%${queries.name}%`);
  if (queries.code) searchParams.set("code", `like.${queries.code}%`);

  const { data, isLoading } = useSWR<ActivityCategoryResult>(
    `/api/activity-categories?${searchParams}`,
    fetcher,
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
