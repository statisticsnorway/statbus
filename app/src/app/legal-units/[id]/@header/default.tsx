import {createClient} from "@/lib/supabase/server";

export default async function LegalUnitHeader({params: {id}}: { readonly params: { id: string } }) {
  const client = createClient()
  const {data: legalUnit} = await client
    .from("legal_unit")
    .select("*")
    .eq("id", id)
    .single()

  return (
    <div className="space-y-0.5">
      <h2 className="text-2xl font-bold tracking-tight">{legalUnit?.name || "Unnamed Organization"}</h2>
      <p className="text-muted-foreground">
        Manage settings for legal unit {id}
      </p>
    </div>
  )
}
