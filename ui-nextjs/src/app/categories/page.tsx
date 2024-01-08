import {createClient} from "@/lib/supabase.server.client";

export default async function CategoriesPage() {
  const client = createClient()
  const {data: categories} = await client.from('activity_category')
    .select('id, label, name, parent_id, updated_at')
    .eq('active', true)
    .limit(25)
    .order('updated_at', {ascending: false})

  return (
    <main className="flex min-h-screen flex-col items-center justify-between p-24">
      <ul role="list" className="divide-y divide-gray-100">
        {categories?.map((category) => (
          <li key={category.id} className="flex justify-between gap-x-6 py-5">
            <div className="flex min-w-0 gap-x-4">
              <div className="min-w-0 flex-auto">
                <p className="text-sm font-semibold leading-6 text-gray-900">{category.name}</p>
                <p className="mt-1 truncate text-xs leading-5 text-gray-500">Parent: {category.parent_id}</p>
              </div>
            </div>
            <div className="hidden shrink-0 sm:flex sm:flex-col sm:items-end">
              <p className="text-sm leading-6 text-gray-900">{category.label}</p>
              <p className="mt-1 text-xs leading-5 text-gray-500">
                Last seen <time dateTime={category.updated_at}>{category.updated_at}</time>
              </p>
            </div>
          </li>
        ))}
      </ul>
    </main>
  )
}
