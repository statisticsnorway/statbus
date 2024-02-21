import {SidebarLink, SidebarNav} from "@/components/sidebar-nav";

export default function Nav ({params: {id}}: { readonly params: { id: string } }) {
  return (
    <SidebarNav>
      <SidebarLink href={`/legal-units/${id}`}>General info</SidebarLink>
      <SidebarLink href={`/legal-units/${id}/contact`}>Contact</SidebarLink>
      <SidebarLink href={`/legal-units/${id}/inspect`}>Inspect</SidebarLink>
    </SidebarNav>
  )
}
