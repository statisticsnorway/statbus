import {SidebarLink, SidebarNav} from "@/components/sidebar-nav";

export default function NavSlot({params: {id}}: { readonly params: { id: string } }) {
    return (
        <SidebarNav>
            <SidebarLink href={`/establishments/${id}`}>General info</SidebarLink>
            <SidebarLink href={`/establishments/${id}/contact`}>Contact</SidebarLink>
            <SidebarLink href={`/establishments/${id}/inspect`}>Inspect</SidebarLink>
        </SidebarNav>
    )
}
