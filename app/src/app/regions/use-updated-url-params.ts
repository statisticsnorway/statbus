import { useEffect } from "react";
import { RegionContextState } from "./region-context";

export default function useUpdatedUrlSearchParams({
  regions: { values, order, pagination },
}: RegionContextState) {
  useEffect(() => {
    const params = Object.entries(values).reduce((params, [name, values]) => {
      if (!values?.length) return params;

      if (values[0] === null) {
        params.set(name, "null");
      } else {
        params.set(name, values.join(","));
      }

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
