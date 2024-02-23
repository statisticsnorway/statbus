import {useEffect} from "react";
import {SearchFilter} from "@/app/search/search.types";

export default function useUpdatedUrlSearchParams(filters: SearchFilter[]) {
  useEffect(() => {
    const urlSearchParams = filters
      .filter(f => f.selected?.length > 0 && f.selected[0] !== '')
      .reduce((acc, f) => {
        acc.set(f.name, f.condition ? `${f.condition}.${f.selected[0]}` : f.selected.join(','));
        return acc;
      }, new URLSearchParams());

    window.history.replaceState(
      {},
      '',
      urlSearchParams.size > 0 ? `?${urlSearchParams}` : window.location.pathname
    );

  }, [filters]);
}
