"use client";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useSearchParams } from "next/navigation";
import { useTimeFrame } from '@/atoms/app-derived';
import { Tables } from '@/lib/database.types';

export default function PopStateHandler() {
  const searchParams = useSearchParams();
  const { setSelectedTimeFrame, timeFrames } = useTimeFrame();

  useGuardedEffect(() => {
    const handlePopState = () => {
      const query = new URLSearchParams(searchParams.toString());
      // The "tc" query param name is kept so existing bookmarks still work;
      // its value is a time_frame ident.
      const tcQueryParam = query.get("tc");

      if (tcQueryParam) {
        const targetTimeFrame = timeFrames.find((tf: Tables<'time_frame'>) => tf.ident === tcQueryParam);
        setSelectedTimeFrame(targetTimeFrame ?? null);
      }
    };

    window.addEventListener('popstate', handlePopState);
    return () => {
      window.removeEventListener('popstate', handlePopState);
    };
  }, [searchParams, setSelectedTimeFrame, timeFrames], 'PopStateHandler:handlePopState');

  return null;
}
