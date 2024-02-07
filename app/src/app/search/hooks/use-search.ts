import useSWR, {Fetcher} from "swr";
import type {SearchFilter, SearchResult} from "@/app/search/search.types";

const fetcher: Fetcher<SearchResult, string> = (...args) => fetch(...args).then(res => res.json())

export default function useSearch(filters: SearchFilter[], fallbackData: SearchResult) {
    const searchParams = filters
        .filter(({selected}) => !!selected?.[0])
        .reduce((params, f) => {
            params.set(f.name, f.postgrestQuery(f));
            return params;
        }, new URLSearchParams());

    const search = useSWR<SearchResult>(`/search/api?${searchParams}`, fetcher, {
        keepPreviousData: true,
        revalidateOnFocus: false,
        fallbackData
    })

    return {search, searchParams}
}
