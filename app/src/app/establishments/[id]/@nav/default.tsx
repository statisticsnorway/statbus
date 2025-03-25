import { SidebarLink, SidebarNav } from "@/components/sidebar-nav";

export default async function NavSlot(
  props: {
    readonly params: Promise<{ id: string }>;
  }
) {
  const params = await props.params;

  const {
    id
  } = params;

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
