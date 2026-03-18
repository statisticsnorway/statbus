import { getBrowserRestClient } from "@/context/RestClientStore";
import { Tables } from "@/lib/database.types";
import useSWR, { Fetcher } from "swr";


const fetcher: Fetcher<Tables<"unit_size">[], string> = async (
    key
) => {
    const client = await getBrowserRestClient();
    const { data, error } = await client
      .from("unit_size")
      .select("*")
      .order("enabled", { ascending: false });

    if(error) {
        throw new Error(error.message, {cause: error})
    }
    return data
}

export function useUnitSizes() {
    const { data, error, isLoading, mutate } = useSWR(
      "/admin/unit_size",
      fetcher
    );
    return {
        unitSizes: data ?? [],
        isLoading,
        error,
        refreshUnitSizes: mutate
    }
}