import {createClient} from "@/lib/supabase/server";

export default async function ActivityCategoriesPage() {
  const client = createClient()
  const {data: activityCategories, count} = await client.from('activity_category_available')
    .select('*', { count: 'exact' })
    .limit(25)

  return (
    <main className="flex flex-col items-center justify-between space-y-8 md:p-24">
      <h1 className="text-xl text-center">Showing top 25 out of total {count} categories</h1>
      <ul className="divide-y divide-gray-100">
        {activityCategories?.map((category) => (
          <li key={category.code} className="flex justify-between gap-x-6 py-3">
            <div className="flex min-w-0 gap-x-4">
              <div className="min-w-0 flex-auto">
                <p className="text-sm truncate font-semibold leading-6 text-gray-900">{category.name}</p>
                <p className="text-sm truncate text-gray-900">{category.standard}</p>
              </div>
            </div>
            <div className="hidden shrink-0 sm:flex sm:flex-col sm:items-end">
              <p className="text-sm leading-6 text-gray-900">{category.label}</p>
              <p className="mt-1 text-xs leading-5 text-gray-500">
                {`${category.path}`}
              </p>
            </div>
          </li>
        ))}
      </ul>
    </main>
  )
}
