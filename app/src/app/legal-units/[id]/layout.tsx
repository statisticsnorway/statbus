import {Metadata} from "next"
import Image from "next/image"
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

export default function SettingsLayout({children, header, params: { id }}: SettingsLayoutProps) {

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
    <>
      <div className="md:hidden">
        <Image
          src="/examples/forms-light.png"
          width={1280}
          height={791}
          alt="Forms"
          className="block dark:hidden"
        />
        <Image
          src="/examples/forms-dark.png"
          width={1280}
          height={791}
          alt="Forms"
          className="hidden dark:block"
        />
      </div>
      <div className="hidden space-y-6 p-10 pb-16 md:block">
        {header}
        <Separator className="my-6"/>
        <div className="flex flex-col space-y-8 lg:flex-row lg:space-x-12 lg:space-y-0">
          <aside className="-mx-4 lg:w-1/5">
            <SidebarNav items={sidebarNavItems}/>
          </aside>
          <div className="flex-1 lg:max-w-2xl">{children}</div>
        </div>
      </div>
    </>
  )
}
