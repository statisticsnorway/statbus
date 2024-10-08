"use client";
import { useEffect } from "react";
import { useSearchParams } from "next/navigation";
import { useTimeContext } from "@/app/time-context";

export default function PopStateHandler() {
  const searchParams = useSearchParams();
  const { setSelectedTimeContext, timeContexts } = useTimeContext();

  useEffect(() => {
    const handlePopState = () => {
      const query = new URLSearchParams(searchParams.toString());
      const tcQueryParam = query.get("tc");

      if (tcQueryParam) {
        const selectedContext = timeContexts.find(
          (timeContext) => timeContext.ident === tcQueryParam
        );
        if (selectedContext) {
          setSelectedTimeContext(selectedContext);
        }
      }
    };

    window.addEventListener('popstate', handlePopState);
    return () => {
      window.removeEventListener('popstate', handlePopState);
    };
  }, [searchParams, setSelectedTimeContext, timeContexts]);

  return null;
}
