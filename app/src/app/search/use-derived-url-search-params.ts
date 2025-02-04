import { useEffect } from "react";
import { SearchContextState } from "@/app/search/search-context";
import { useRouter } from "next/navigation";

export default function useDerivedUrlSearchParams({
  searchState: { appSearchParams, order, pagination },
}: SearchContextState) {
  const router = useRouter();
  useEffect(() => {
    const params = Object.entries(appSearchParams).reduce((params, [name, values]) => {
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
    router.replace(params.size > 0 ? `?${params}` : window.location.pathname, {
      scroll: false,
    });
  }, [appSearchParams, order, pagination, router]);
}
