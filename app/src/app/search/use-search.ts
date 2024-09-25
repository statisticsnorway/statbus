import useSWR, { Fetcher } from "swr";

import { useTimeContext } from "@/app/use-time-context";
import { useCustomConfigContext } from "../use-custom-config-context";

const fetcher: Fetcher<SearchResult, string> = (...args) =>
  fetch(...args).then((res) => res.json());

export default function useSearch(searchFilterState: SearchState) {
  const { selectedPeriod } = useTimeContext();
  const { statDefinitions } = useCustomConfigContext();
  const { order, pagination, queries } = searchFilterState;

  const searchParams = Object.entries(queries ?? {})
    .filter(([, query]) => !!query)
    .reduce((params, [name, query]) => {
      params.set(name, query!);
      return params;
    }, new URLSearchParams());

  const api_param_name = statDefinitions?.find(
    ({ code }) => code === order.name
  )
    ? `stats_summary->${order.name}->sum`
    : order.name;

  if (api_param_name && order.direction) {
    searchParams.set("order", `${api_param_name}.${order.direction}`);
  }

  if (selectedPeriod) {
    searchParams.set("valid_from", `lte.${selectedPeriod.valid_on}`);
    searchParams.set("valid_to", `gte.${selectedPeriod.valid_on}`);
  }

  if (pagination.pageNumber && pagination.pageSize) {
    const offset = (pagination.pageNumber - 1) * pagination.pageSize;
    searchParams.set("limit", `${pagination.pageSize}`);
    searchParams.set("offset", `${offset}`);
  }

  const search = useSWR<SearchResult>(`/api/search?${searchParams}`, fetcher, {
    keepPreviousData: true,
    revalidateOnFocus: false,
  });

  return { search, searchParams };
}
