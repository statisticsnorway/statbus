import {Button} from "@/components/ui/button";
import {useSearchContext} from "@/app/search/search-provider";
import {Popover, PopoverContent, PopoverTrigger} from "@/components/ui/popover";
import {Combine, ShoppingBasket, Trash} from "lucide-react";
import {Command} from "cmdk";
import {CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList} from "@/components/ui/command";
import * as React from "react";
import {cn} from "@/lib/utils";
import {useRouter} from "next/navigation";

export default function SearchBulkActionButton() {
  const router = useRouter()
  const {selected, clearSelected} = useSearchContext();

  const isEligibleForCombination = selected.length === 2
    && selected.find((unit) => unit.unit_type === 'enterprise')
    && selected.find((unit) => unit.unit_type === 'legal_unit');

  const setPrimaryLegalUnitForEnterprise = async () => {
    const legalUnit = selected.find((unit) => unit.unit_type === 'legal_unit');
    const enterprise = selected.find((unit) => unit.unit_type === 'enterprise');

    if (!legalUnit || !enterprise) {
      console.error('failed to set primary legal unit for enterprise due to missing legal unit or enterprise');
      return;
    }

    try {
      const response = await fetch(`/api/legal-units/${legalUnit.unit_id}/primary`, {
        method: 'POST',
        body: JSON.stringify(enterprise),
      })

      if (!response.ok) {
        console.error('failed to set primary legal unit for enterprise');
        return;
      }

      router.push(`/enterprises/${enterprise.unit_id}`);

    } catch (e) {
      console.error('failed to set primary legal unit for enterprise', e);
    }
  }

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button disabled={!selected.length} variant="secondary" size="sm" className="border-dashed space-x-2">
          <ShoppingBasket className="mr-2 h-4 w-4"/>
          {selected.length} units in basket
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-auto max-w-[350px] md:max-w-[500px] p-0" align="start">
        <Command>
          <CommandInput placeholder="Select action"/>
          <CommandList>
            <CommandEmpty>No command found.</CommandEmpty>
            <CommandGroup>
              <CommandItem
                disabled={!isEligibleForCombination}
                onSelect={setPrimaryLegalUnitForEnterprise}
                className={cn("flex-col items-start space-y-1", !isEligibleForCombination && 'opacity-50')}
              >
                <div className="flex space-x-2 items-center">
                  <Combine className="h-4 w-4"/>
                  <span>Combine units</span>
                </div>
                <span className="text-xs">One Legal Unit and one Enterprise</span>
              </CommandItem>
            </CommandGroup>
            <CommandGroup>
              <CommandItem onSelect={clearSelected} className="space-x-2">
                <Trash className="h-4 w-4"/>
                <span>Clear selection</span>
              </CommandItem>
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  )
}
