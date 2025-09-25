"use client";
import { Input } from "@/components/ui/input";
import { useSearchQuery } from "@/atoms/search";
import { useDebouncedCallback } from "@/hooks/use-debounced-callback";
import { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

export default function FullTextSearchFilter() {
  const { query, updateSearchQuery } = useSearchQuery();
  const [localQuery, setLocalQuery] = useState(query);

  // Sync global state to local state when it changes externally
  useGuardedEffect(() => {
    setLocalQuery(query);
  }, [query], 'FullTextSearchFilter:syncToLocal');

  // Debounced update to global state
  const debouncedUpdate = useDebouncedCallback((newValue: string) => {
    updateSearchQuery(newValue);
  }, 300);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newValue = e.target.value;
    setLocalQuery(newValue); // Update local state immediately for responsiveness
    debouncedUpdate(newValue); // Debounce the update to the global state
  };

  return (
    <Input
      type="text"
      placeholder="Find units by name"
      className="h-9 w-full md:max-w-[200px]"
      id="full-text-search"
      name="full-text-search"
      value={localQuery}
      onChange={handleChange}
    />
  );
}
