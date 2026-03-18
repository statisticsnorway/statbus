import { getBrowserRestClient } from "@/context/RestClientStore";
import { Tables } from "@/lib/database.types";
import useSWR, { Fetcher } from "swr";


const fetcher: Fetcher<Tables<"data_source">[], string> = async (
    key
) => {
    const client = await getBrowserRestClient();
    const { data, error } = await client
      .from("data_source")
      .select("*")
      .order("enabled", { ascending: false });

    if(error) {
        throw new Error(error.message, {cause: error})
    }
    return data
}

export function useDataSources() {
    const { data, error, isLoading, mutate } = useSWR(
      "/admin/data_source",
      fetcher
    );
    return {
        dataSources: data ?? [],
        isLoading,
        error,
        refreshDataSources: mutate
    }
}