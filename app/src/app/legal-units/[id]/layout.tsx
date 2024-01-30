import {Metadata} from "next"
import {Separator} from "@/components/ui/separator";
import {SidebarNav} from "@/app/legal-units/components/sidebar-nav";
import {ReactNode, useCallback} from "react";

export const metadata: Metadata = {
  title: "Legal Unit"
}

interface SettingsLayoutProps {
  children: ReactNode,
  header: ReactNode,
  params: { id: string }
}

export default function SettingsLayout({children, header, params: {id}}: SettingsLayoutProps) {

  const createSidebarNavItems = useCallback(() => {
    return [
      {
        title: "General info",
        href: `/legal-units/${id}`
      },
      {
        title: "Contact",
        href: `/legal-units/${id}/contact`
      }
    ]
  }, [id])

  const sidebarNavItems = createSidebarNavItems()

  return (
    <main className="py-8 px-2 md:py-24 space-y-6 max-w-5xl mx-auto">
      {header}
      <Separator className="my-6"/>
      <div className="flex flex-col space-y-8 lg:flex-row lg:space-x-12 lg:space-y-0">
        <aside className="lg:-mx-4 lg:w-1/5">
          <SidebarNav items={sidebarNavItems}/>
        </aside>
        <div className="flex-1 space-y-8">{children}</div>
      </div>
    </main>
  )
}
