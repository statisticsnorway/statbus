import { SidebarLink, SidebarNav } from "@/components/sidebar-nav";

export default function NavSlot({
  params: { id },
}: {
  readonly params: { id: string };
}) {
  return (
    <SidebarNav>
      <SidebarLink href={`/establishments/${id}`}>Identification</SidebarLink>
      <SidebarLink href={`/establishments/${id}/contact`}>Contact</SidebarLink>
      <SidebarLink href={`/establishments/${id}/demographic`}>
        Demographic
      </SidebarLink>
      <SidebarLink href={`/establishments/${id}/classifications`}>
        Classifications
      </SidebarLink>
      <SidebarLink href={`/establishments/${id}/statistical-variables`}>
        Statistical variables
      </SidebarLink>
      <SidebarLink href={`/establishments/${id}/links`}>
        Links and external references
      </SidebarLink>
      <SidebarLink href={`/establishments/${id}/inspect`}>Inspect</SidebarLink>
    </SidebarNav>
  );
}
