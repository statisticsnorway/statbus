"use client";
import { useEffect } from "react";
import { useSearchParams } from "next/navigation";
import { useTimeContext } from "@/app/time-context";

export default function PopStateHandler() {
  const searchParams = useSearchParams();
  const { setSelectedTimeContextFromIdent } = useTimeContext();

  useEffect(() => {
    const handlePopState = () => {
      const query = new URLSearchParams(searchParams.toString());
      const tcQueryParam = query.get("tc");

      if (tcQueryParam) {
        setSelectedTimeContextFromIdent(tcQueryParam);
      }
    };

    window.addEventListener('popstate', handlePopState);
    return () => {
      window.removeEventListener('popstate', handlePopState);
    };
  }, [searchParams, setSelectedTimeContextFromIdent]);

  return null;
}
