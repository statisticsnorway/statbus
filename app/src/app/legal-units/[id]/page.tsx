import {Metadata} from "next";
import {notFound} from "next/navigation";
import GeneralInfoForm from "@/app/legal-units/[id]/general-info/general-info-form";
import {Separator} from "@/components/ui/separator";
import {getLegalUnitById} from "@/app/legal-units/[id]/requests";

export const metadata: Metadata = {
  title: "Legal Unit | General Info"
}

export default async function LegalUnitGeneralInfoPage({params: {id}}: { readonly params: { id: string } }) {
  const unit = await getLegalUnitById(id)

  if (!unit) {
    notFound()
  }

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-medium">General Info</h3>
        <p className="text-sm text-muted-foreground">
          General information such as name, id, sector and primary activity.
        </p>
      </div>
      <Separator/>
      <GeneralInfoForm values={unit} id={id}/>
    </div>
  )
}
