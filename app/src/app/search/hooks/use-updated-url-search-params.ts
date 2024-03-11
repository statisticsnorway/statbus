import {useEffect} from "react";
import type {SearchContextState} from "@/app/search/search-provider";

export default function useUpdatedUrlSearchParams({search: {filters, order, pagination}}: SearchContextState) {
  useEffect(() => {
    const urlSearchParams = filters
      .filter(f => f.selected?.length > 0 && f.selected[0] !== '')
      .reduce((acc, f) => {
        acc.set(f.name, f.condition ? `${f.condition}.${f.selected[0]}` : f.selected.join(','));
        return acc;
      }, new URLSearchParams());

    if (order.name) {
      urlSearchParams.set('order', `${order.name}.${order.direction}`);
    }

    if (pagination.pageNumber) {
      urlSearchParams.set('page', `${pagination.pageNumber}`)
    }
    
    window.history.replaceState(
      {},
      '',
      urlSearchParams.size > 0 ? `?${urlSearchParams}` : window.location.pathname
    );
  }, [filters, order, pagination]);
}
