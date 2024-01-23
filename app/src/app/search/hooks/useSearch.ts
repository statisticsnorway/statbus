import useSWR, {Fetcher} from "swr";
import type {SearchFilter, SearchResult} from "@/app/search/search.types";

const fetcher: Fetcher<SearchResult, string> = (...args) => fetch(...args).then(res => res.json())

export default function useSearch(prompt: string, filters: SearchFilter[], fallbackData: SearchResult) {

    const searchParams = new URLSearchParams()

    if (prompt) {
        searchParams.set('name', `ilike.*${prompt}*`)
    }

    filters
        .filter(({selected}) => selected.length)
        .forEach(({name, selected, condition}) => {

            if (condition === 'in') {
                searchParams.set(name, `${condition}.(${selected.join(',')})`)
                return
            }

            searchParams.set(name, `${condition}.${selected.join(',')}`)
        })

    return useSWR<SearchResult>(`/search/api?${searchParams}`, fetcher, {
        keepPreviousData: true,
        revalidateOnFocus: false,
        fallbackData
    })
}
