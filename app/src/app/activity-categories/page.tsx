import { Metadata } from "next";
import { createClient } from "@/lib/supabase/server";
import { cn } from "@/lib/utils";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";

export const metadata: Metadata = {
  title: "StatBus | Activity Category Standard Codes",
};

export default async function ActivityCategoriesPage() {
  const client = createClient();

  const { data: settings, error } = await client
    .from("settings")
    .select("activity_category_standard_id")
    .single();

  if (error) {
    throw new Error("failed to fetch activity category standard id setting", {
      cause: error,
    });
  }

  const { data: categories } = await client
    .from("activity_category")
    .select()
    .eq("level", 1)
    .eq("standard_id", settings.activity_category_standard_id)
    .order("path", { ascending: true });

  return (
    <main className="mx-auto flex max-w-5xl flex-col px-2 py-8 md:py-24 w-full">
      <h1 className="mb-12 text-center text-2xl">
        Activity Category Standard Codes
      </h1>

      <Accordion type="single" collapsible>
        {categories?.map(({ id, name, active, label, description }) => (
          <AccordionItem key={id} value={name}>
            <AccordionTrigger>
              <div
                className={cn(
                  "flex items-center gap-4 text-left",
                  !active && "text-gray-400"
                )}
              >
                <span className="text-2xl">{label}</span>
                <span>{name}</span>
              </div>
            </AccordionTrigger>
            <AccordionContent>{description}</AccordionContent>
          </AccordionItem>
        ))}
      </Accordion>
    </main>
  );
}
