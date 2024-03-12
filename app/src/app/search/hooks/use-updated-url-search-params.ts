import { useEffect } from "react";
import type { SearchContextState } from "@/app/search/search-provider";

export default function useUpdatedUrlSearchParams({
  search: { filters, order, pagination },
}: SearchContextState) {
  useEffect(() => {
    const params = filters
      .filter((f) => f.selected?.[0]!!)
      .reduce((acc, f) => {
        acc.set(f.name, `${f.operator}.${f.selected.join(",")}`);
        return acc;
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
  }, [filters, order, pagination]);
}
