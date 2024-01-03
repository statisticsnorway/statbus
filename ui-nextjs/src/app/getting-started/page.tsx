import {createClient} from "@/app/auth/_lib/supabase.server.client";
import CategoryStandardForm from "@/app/getting-started/_lib/CategoryStandardForm";

export default async function Home() {
  const client = createClient()

  const {data: settings} = await client.from('settings')
    .select('id, activity_category_standard(id,name)')

  const {data: standards} = await client.from('activity_category_standard')
    .select('id, name')

  return (
    <main className="flex flex-col items-center p-24">
      {
        !settings?.length && (
          // @ts-ignore
          <CategoryStandardForm settings={settings} standards={standards} />
        )
      }

      {
        settings?.length ? (
          <div>
            <h2>Settings</h2>
            <pre>{JSON.stringify(settings, null, 2)}</pre>
          </div>
        ) : null
      }
    </main>
  )
}
