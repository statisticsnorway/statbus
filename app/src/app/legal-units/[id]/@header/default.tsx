import {getLegalUnitById} from "@/app/legal-units/[id]/requests";

export default async function LegalUnitHeader({params: {id}}: { readonly params: { id: string } }) {
  const unit = await getLegalUnitById(id);

  return (
    <div className="space-y-0.5">
      <h2 className="text-2xl font-bold tracking-tight">{unit?.name || "Unnamed Organization"}</h2>
      <p className="text-muted-foreground">
        Manage settings for unit {id}
      </p>
    </div>
  )
}
