import {DetailsPage} from "@/components/statistical-unit-details/details-page";
import {notFound} from "next/navigation";
import {getEstablishmentById} from "@/components/statistical-unit-details/requests";
import {Button} from "@/components/ui/button";
import {createClient} from "@/lib/supabase/server";
import {revalidatePath} from "next/cache";

export default async function EstablishmentGeneralInfoPage({params: {id}}: { readonly params: { id: string } }) {
  const {establishment, error} = await getEstablishmentById(id);

  if (error) {
    throw new Error(error.message, {cause: error})
  }

  if (!establishment) {
    notFound()
  }

  async function setPrimary(id: number) {
    'use server';
    const client = createClient();
    const {data, error} = await client.rpc('set_primary_establishment_for_legal_unit', {establishment_id: id})

    if (error) {
      console.error('failed to set primary establishment', error)
      return
    }

    console.debug('primary establishment updated', data)
    return revalidatePath("/establishments/[id]", "page")
  }

  return (
    <DetailsPage title="General Info" subtitle="General information such as name, sector">
      <p className="bg-gray-50 p-12 text-sm text-center">
        This section will show general information for {establishment.name}
      </p>

      <form action={setPrimary.bind(null, establishment.id)}>
        <Button type="submit">Set as primary establishment</Button>
      </form>
    </DetailsPage>
  )
}

