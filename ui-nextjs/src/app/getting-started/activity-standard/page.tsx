import {createClient} from "@/lib/supabase.server.client";
import CategoryStandardForm from "@/app/getting-started/activity-standard/_components/CategoryStandardForm";

export default async function Home() {
  const client = createClient()

  const {data: standards} = await client.from('activity_category_standard')
    .select('id, name')

  const {data: settings} = await client.from('settings')
    .select('id, activity_category_standard(id,name)')

  // @ts-ignore
  return <CategoryStandardForm standards={standards} settings={settings}/>
}
