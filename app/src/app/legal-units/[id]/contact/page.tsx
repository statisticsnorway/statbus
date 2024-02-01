import {Metadata} from "next";
import {notFound} from "next/navigation";
import {Separator} from "@/components/ui/separator";
import ContactInfoForm from "@/app/legal-units/[id]/contact/contact-info-form";
import {getLegalUnitById} from "@/app/legal-units/[id]/requests";

export const metadata: Metadata = {
  title: "Legal Unit | Contact"
}

export default async function LegalUnitContactPage({params: {id}}: { readonly params: { id: string } }) {
  const unit = await getLegalUnitById(id);

  if (!unit) {
    notFound()
  }

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-medium">Contact Info</h3>
        <p className="text-sm text-muted-foreground">
          Contact information such as email, phone, and addresses.
        </p>
      </div>
      <Separator/>
      <ContactInfoForm values={unit} id={id}/>
    </div>
  )
}
