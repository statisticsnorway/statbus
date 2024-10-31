import { Button } from "@/components/ui/button";
import { PlusCircle } from "lucide-react";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { createSupabaseSSRClient } from "@/utils/supabase/server";
import { ExternalIdentInputs } from "./external-ident-inputs";

export default async function ExternalIdentFilter() {
  const client = await createSupabaseSSRClient();
  const externalIdentTypes = await client
    .from("external_ident_type_ordered")
    .select();

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          className="space-x-2 border-dashed p-2 h-9"
        >
          <PlusCircle className="mr-2 h-4 w-4" />
          External Identifiers
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-80 p-4" align="start">
        <div className="space-y-4">
          <ExternalIdentInputs externalIdentTypes={externalIdentTypes.data ?? []} />
        </div>
      </PopoverContent>
    </Popover>
  );
}
