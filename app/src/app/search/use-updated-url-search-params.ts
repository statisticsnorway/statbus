import { useEffect } from "react";
import { SearchContextState } from "@/app/search/search-context";

export default function useUpdatedUrlSearchParams({
  search: { values, order, pagination },
}: SearchContextState) {
  useEffect(() => {
    const params = Object.entries(values ?? {})
      .filter(([, values]) => values?.length > 0)
      .reduce((params, [name, values]) => {
        params.set(name, values.join(","));
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
  }, [values, order, pagination]);
}
