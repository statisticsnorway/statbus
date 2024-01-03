import {createClient} from "@/app/auth/_lib/supabase.server.client";
import CategoryStandardForm from "@/app/getting-started/_components/CategoryStandardForm";

export default async function Home() {
  const client = createClient()

  const {data: standards} = await client.from('activity_category_standard')
    .select('id, name')

  // @ts-ignore
  return <CategoryStandardForm standards={standards}/>
}
