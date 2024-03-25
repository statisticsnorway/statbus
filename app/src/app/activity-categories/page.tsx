import { Metadata } from "next";
import { createClient } from "@/lib/supabase/server";
import { cn } from "@/lib/utils";

export const metadata: Metadata = {
  title: "StatBus | Activity Category Standard Codes",
};

export default async function ActivityCategoriesPage() {
  const client = createClient();

  const { data: activityCategories } = await client
    .from("activity_category_available")
    .select();

  const activityCategoryFirstLetters = new Set(
    activityCategories
      ?.map((activity) => activity.label?.charAt(0))
      .filter((char) => char && /^[A-Za-z]$/.test(char))
  );

  return (
    <main className="mx-auto flex max-w-5xl flex-col px-2 py-8 md:py-24">
      <h1 className="mb-12 text-center text-2xl">
        Activity Category Standard Codes
      </h1>

      <ul className="flex justify-center gap-3 text-xl font-semibold mb-12">
        {Array.from(activityCategoryFirstLetters).map((letter) => (
          <li key={letter}>
            <a href={`#${letter}`}>{letter}</a>
          </li>
        ))}
      </ul>

      <ul>
        {activityCategories?.map((activity) => (
          <li
            key={activity.id}
            id={activity.label ?? undefined}
            className={cn(
              "py-2 px-4",
              activity.parent_code === null ? "bg-ssb-light font-semibold" : ""
            )}
          >
            <div className="flex items-center">
              <span className="flex-1">{activity.name}</span>
              <span>{activity.label}</span>
            </div>
          </li>
        ))}
      </ul>
    </main>
  );
}
