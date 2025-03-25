import { SidebarLink, SidebarNav } from "@/components/sidebar-nav";

export default async function Nav(
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
      <SidebarLink href={`/legal-units/${id}`}>Identification</SidebarLink>
      <SidebarLink href={`/legal-units/${id}/contact`}>Contact</SidebarLink>
      <SidebarLink href={`/legal-units/${id}/demographic`}>
        Demographic
      </SidebarLink>
      <SidebarLink href={`/legal-units/${id}/classifications`}>
        Classifications
      </SidebarLink>
      <SidebarLink href={`/legal-units/${id}/statistical-variables`}>
        Statistical variables
      </SidebarLink>
      <SidebarLink href={`/legal-units/${id}/links`}>
        Links and external references
      </SidebarLink>
      <SidebarLink href={`/legal-units/${id}/inspect`}>Inspect</SidebarLink>
    </SidebarNav>
  );
}
