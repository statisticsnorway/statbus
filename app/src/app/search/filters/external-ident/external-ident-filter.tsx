import { Button } from "@/components/ui/button";
import { PlusCircle } from "lucide-react";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { createPostgRESTSSRClient } from "@/utils/auth/postgrest-client-server";
import { ExternalIdentInputs } from "./external-ident-inputs";
import { ActiveExternalIdentBadges } from "./active-external-ident-badges";

export default async function ExternalIdentFilter() {
  const client = await createPostgRESTSSRClient();
  const externalIdentTypes = await client
    .from("external_ident_type_active")
    .select();

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          className="space-x-2 border-dashed p-2 h-9"
        >
          <PlusCircle className="mr-2 h-4 w-4" />
          Identifiers
          <ActiveExternalIdentBadges externalIdentTypes={externalIdentTypes.data ?? []} />
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
