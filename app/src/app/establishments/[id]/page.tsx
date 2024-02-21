import {getEstablishmentById} from "@/app/establishments/[id]/establishment-requests";
import DataDump from "@/components/data-dump";
import {Separator} from "@/components/ui/separator";

export default async function EstablishmentDetailsPage({params: {id}}: { readonly params: { id: string } }) {
  const unit = await getEstablishmentById(id);
  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-medium">Data dump</h3>
        <p className="text-sm text-muted-foreground">
          This section shows the raw data we have on {unit?.name}.
        </p>
      </div>
      <Separator/>
      {
        unit != null ? <DataDump data={unit}/> : null
      }
    </div>
  )
}
