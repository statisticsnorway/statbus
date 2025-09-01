"use client";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useSearchParams } from "next/navigation";
import { useTimeContext } from '@/atoms/app';
import { Tables } from '@/lib/database.types';

export default function PopStateHandler() {
  const searchParams = useSearchParams();
  // const { setSelectedTimeContextFromIdent } = useTimeContext(); // Original
  // The new useTimeContext returns: selectedTimeContext, setSelectedTimeContext, timeContexts, defaultTimeContext
  // Need to adapt setSelectedTimeContextFromIdent.
  // For now, let's assume setSelectedTimeContext can take an ident or the object.
  // The original setSelectedTimeContextFromIdent likely found the TC object by ident.
  const { setSelectedTimeContext, timeContexts } = useTimeContext();


  useGuardedEffect(() => {
    const handlePopState = () => {
      const query = new URLSearchParams(searchParams.toString());
      const tcQueryParam = query.get("tc");

      if (tcQueryParam) {
        // setSelectedTimeContextFromIdent(tcQueryParam); // Original
        // New logic: find time context by ident and set it
        const targetTimeContext = timeContexts.find((tc: Tables<'time_context'>) => tc.ident === tcQueryParam);
        if (targetTimeContext) {
          setSelectedTimeContext(targetTimeContext);
        } else {
          // Fallback or error handling if tcQueryParam is invalid
          setSelectedTimeContext(null); 
        }
      }
    };

    window.addEventListener('popstate', handlePopState);
    return () => {
      window.removeEventListener('popstate', handlePopState);
    };
  }, [searchParams, setSelectedTimeContext, timeContexts], 'PopStateHandler:handlePopState');

  return null;
}
