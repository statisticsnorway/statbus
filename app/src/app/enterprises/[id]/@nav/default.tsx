import {SidebarLink, SidebarNav} from "@/components/sidebar-nav";

export default function NavSlot({params: {id}}: { readonly params: { id: string } }) {
    return (
        <SidebarNav>
            <SidebarLink href={`/enterprises/${id}`}>General info</SidebarLink>
            <SidebarLink href={`/enterprises/${id}/contact`}>Contact</SidebarLink>
            <SidebarLink href={`/enterprises/${id}/inspect`}>Inspect</SidebarLink>
        </SidebarNav>
    )
}
