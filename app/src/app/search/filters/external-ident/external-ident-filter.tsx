"use client";
import { Button } from "@/components/ui/button";
import { PlusCircle } from "lucide-react";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { ExternalIdentInputs } from "./external-ident-inputs";
import { ActiveExternalIdentBadges } from "./active-external-ident-badges";
import { useSearchPageData } from "@/atoms/search";

export default function ExternalIdentFilter() {
  const { allExternalIdentTypes } = useSearchPageData();

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          className="space-x-2 border-dashed p-2 h-9"
        >
          <PlusCircle className="mr-2 h-4 w-4" />
          Identifiers
          <ActiveExternalIdentBadges externalIdentTypes={allExternalIdentTypes ?? []} />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-80 p-4" align="start">
        <div className="space-y-4">
          <ExternalIdentInputs externalIdentTypes={allExternalIdentTypes ?? []} />
        </div>
      </PopoverContent>
    </Popover>
  );
}
