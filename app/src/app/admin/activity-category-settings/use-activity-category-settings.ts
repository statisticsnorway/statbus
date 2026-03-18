import { getBrowserRestClient } from "@/context/RestClientStore";
import { Tables } from "@/lib/database.types";
import useSWR, { Fetcher } from "swr";


const fetcher: Fetcher<Tables<"activity_category_standard">[], string> = async (
    key
) => {
    const client = await getBrowserRestClient();
    const { data, error } = await client
      .from("activity_category_standard")
      .select("*")
      .order("enabled", { ascending: false });

    if(error) {
        throw new Error(error.message, {cause: error})
    }
    return data
}

export function useActivityCategorySettings() {
    const { data, error, isLoading, mutate } = useSWR(
      "/admin/activity_category_standard",
      fetcher
    );
    return {
      activityCategorySettings: data ?? [],
      isLoading,
      error,
      refreshActivityCategorySettings: mutate,
    };
}