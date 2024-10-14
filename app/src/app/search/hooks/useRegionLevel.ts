import { useState } from "react";

export function useRegionLevel(initialLevel: number = 1) {
  const [regionLevel, setRegionLevel] = useState<number>(initialLevel);
  return { regionLevel, setRegionLevel };
}
