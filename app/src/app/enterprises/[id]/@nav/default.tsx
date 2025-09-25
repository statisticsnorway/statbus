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
      <SidebarLink href={`/enterprises/${id}`}>Identification</SidebarLink>
      <SidebarLink href={`/enterprises/${id}/contact`}>Contact</SidebarLink>
      <SidebarLink href={`/enterprises/${id}/demographic`}>
        Demographic
      </SidebarLink>
      <SidebarLink href={`/enterprises/${id}/classifications`}>
        Classifications
      </SidebarLink>
      <SidebarLink href={`/enterprises/${id}/statistical-variables`}>
        Statistical variables
      </SidebarLink>
      <SidebarLink href={`/enterprises/${id}/history`}>History</SidebarLink>
      <SidebarLink href={`/enterprises/${id}/links`}>
        Links and external references
      </SidebarLink>
      <SidebarLink href={`/enterprises/${id}/inspect`}>Inspect</SidebarLink>
    </SidebarNav>
  );
}
