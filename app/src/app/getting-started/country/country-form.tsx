"use client";
import { zodResolver } from "@hookform/resolvers/zod";
import * as z from "zod";
import { Button } from "@/components/ui/button";
import { Form, FormControl, FormField, FormItem } from "@/components/ui/form";
import { useForm } from "react-hook-form";
import { useRouter } from "next/navigation";
import { useSetAtom } from "jotai";
import {
  gettingStartedSelectedCountryAtom,
  settingsAtomAsync,
} from "@/atoms/getting-started";
import { Tables } from "@/lib/database.types";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Check, ChevronsUpDown } from "lucide-react";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import { useState } from "react";
import { cn } from "@/lib/utils";
import { setSettings } from "../getting-started-server-actions";

interface CountryFormProps {
  readonly countries: Tables<"country">[] | null;
  readonly settings: Tables<"settings">[] | null;
}

const FormSchema = z.object({
  country_id: z.coerce.number({
    required_error: "You need to select a country",
  }),
});

export default function CountryForm({ countries, settings }: CountryFormProps) {
  const [open, setOpen] = useState(false);
  const setSelectedCountry = useSetAtom(gettingStartedSelectedCountryAtom);
  const form = useForm<z.infer<typeof FormSchema>>({
    resolver: zodResolver(FormSchema),
    defaultValues: {
      country_id: settings?.[0]?.country_id,
    },
  });
  const router = useRouter();
  const refreshSettings = useSetAtom(settingsAtomAsync);

  async function onSubmit({ country_id }: z.infer<typeof FormSchema>) {
    if (settings?.[0]) {
      const formData = new FormData();
      formData.append("country_id", country_id.toString(10));
      formData.append(
        "activity_category_standard_id",
        settings[0].activity_category_standard_id.toString(10)
      );
      const result = await setSettings(formData);
      if (result.success) {
        await refreshSettings();
        setSelectedCountry(null);
      }
    } else {
      const selected = countries?.find((c) => c.id === country_id);
      if (selected) {
        setSelectedCountry(selected.id);
      }
      // No existing settings - store in Jotai
    }
    router.push("/getting-started/activity-standard");
  }
  return (
    <Form {...form}>
      <form
        onSubmit={form.handleSubmit(onSubmit)}
        className="space-y-6 bg-ssb-light p-6"
      >
        <FormField
          control={form.control}
          name="country_id"
          render={({ field }) => (
            <FormItem className="flex flex-col">
              <legend>Select your country</legend>
              <Popover open={open} onOpenChange={setOpen}>
                <PopoverTrigger asChild>
                  <FormControl>
                    <Button
                      variant="outline"
                      role="combobox"
                      className={cn(
                        "w-full justify-between mt-1",
                        !field.value && "text-muted-foreground"
                      )}
                    >
                      {field.value
                        ? countries?.find((c) => c.id === field.value)?.name
                        : "Select country"}
                      <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
                    </Button>
                  </FormControl>
                </PopoverTrigger>
                <PopoverContent className="w-(--radix-popover-trigger-width) p-0">
                  <Command>
                    <CommandInput placeholder="Search country..." />
                    <CommandList>
                      <CommandEmpty>No country found.</CommandEmpty>
                      <CommandGroup>
                        {countries?.map((country) => (
                          <CommandItem
                            value={country.name}
                            key={country.id}
                            onSelect={() => {
                              form.setValue("country_id", country.id);
                              setOpen(false);
                            }}
                          >
                            <Check
                              className={cn(
                                "mr-2 h-4 w-4",
                                country.id === field.value
                                  ? "opacity-100"
                                  : "opacity-0"
                              )}
                            />
                            {country.name}
                          </CommandItem>
                        ))}
                      </CommandGroup>
                    </CommandList>
                  </Command>
                </PopoverContent>
              </Popover>
            </FormItem>
          )}
        />
        <div className="space-x-3">
          <Button type="submit">Confirm</Button>
        </div>
      </form>
    </Form>
  );
}
