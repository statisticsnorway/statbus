import { useEffect } from "react";
import { SearchContextState } from "@/app/search/search-context";

export default function useUpdatedUrlSearchParams({
  search: { queries, order, pagination },
}: SearchContextState) {
  useEffect(() => {
    const params = Object.entries(queries ?? {})
      .filter(([, query]) => !!query)
      .reduce((params, [name, query]) => {
        params.set(name, query!);
        return params;
      }, new URLSearchParams());

    if (order.name) {
      params.set("order", `${order.name}.${order.direction}`);
    }

    if (pagination.pageNumber) {
      params.set("page", `${pagination.pageNumber}`);
    }

    window.history.replaceState(
      {},
      "",
      params.size > 0 ? `?${params}` : window.location.pathname
    );
  }, [queries, order, pagination]);
}
