import {Metadata} from "next";
import {createClient} from "@/lib/supabase/server";
import {notFound} from "next/navigation";

export const metadata: Metadata = {
  title: "Legal Unit | Contact"
}

export default async function LegalUnitContactPage({params: {id}}: { params: { id: string } }) {
  const client = createClient()
  const {data: legalUnit} = await client
    .from("legal_unit")
    .select("*")
    .eq("id", id)
    .single()

  if (!legalUnit) {
    notFound()
  }

  return (
    <>Contact info goes here</>
  )
}
