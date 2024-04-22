import useSWR, { Fetcher } from "swr";

const fetcher: Fetcher<RegionResult, string> = (...args) =>
  fetch(...args).then((res) => res.json());

export default function useRegion(regionFilterState: RegionState) {
  const { order, pagination, queries } = regionFilterState;

  const searchParams = Object.entries(queries ?? {})
    .filter(([, query]) => !!query)
    .reduce((params, [name, query]) => {
      params.set(name, query!);
      return params;
    }, new URLSearchParams());

  if (order.name && order.direction) {
    searchParams.set("order", `${order.name}.${order.direction}`);
  }

  if (pagination.pageNumber && pagination.pageSize) {
    const offset = (pagination.pageNumber - 1) * pagination.pageSize;
    searchParams.set("limit", `${pagination.pageSize}`);
    searchParams.set("offset", `${offset}`);
  }

  const regions = useSWR<RegionResult>(`/api/region?${searchParams}`, fetcher, {
    keepPreviousData: true,
    revalidateOnFocus: false,
  });

  return { regions, searchParams };
}
