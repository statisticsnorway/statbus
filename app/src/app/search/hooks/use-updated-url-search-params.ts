import {useEffect} from "react";
import type {SearchContextState} from "@/app/search/search-provider";

export default function useUpdatedUrlSearchParams({searchFilters, searchOrder}: SearchContextState) {
  useEffect(() => {
    const urlSearchParams = searchFilters
      .filter(f => f.selected?.length > 0 && f.selected[0] !== '')
      .reduce((acc, f) => {
        acc.set(f.name, f.condition ? `${f.condition}.${f.selected[0]}` : f.selected.join(','));
        return acc;
      }, new URLSearchParams());

    if (searchOrder.name) {
      urlSearchParams.set('order', `${searchOrder.name}.${searchOrder.direction}`);
    }

    window.history.replaceState(
      {},
      '',
      urlSearchParams.size > 0 ? `?${urlSearchParams}` : window.location.pathname
    );

  }, [searchFilters, searchOrder]);
}
