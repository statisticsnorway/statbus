import { createClient } from "@/lib/supabase/server";
import { NavItem } from "@/app/getting-started/@progress/nav-item";

export default async function SetupStatus() {
  const client = createClient();
  const { data: settings, count: numberOfSettings } = await client
    .from("settings")
    .select("activity_category_standard(id,name)", { count: "exact" })
    .limit(1);

  const { count: numberOfRegions } = await client
    .from("region")
    .select("*", { count: "exact" })
    .limit(0);

  const { count: numberOfLegalUnits } = await client
    .from("legal_unit")
    .select("*", { count: "exact" })
    .limit(0);

  const { count: numberOfEstablishments } = await client
    .from("establishment")
    .select("*", { count: "exact" })
    .limit(0);

  const { count: numberOfCustomActivityCategoryCodes } = await client
    .from("activity_category_available_custom")
    .select("*", { count: "exact" })
    .limit(0);

  const { count: numberOfCustomSectors } = await client
    .from("sector_custom")
    .select("*", { count: "exact" })
    .limit(0);

  return (
    <nav>
      <ul className="text-sm">
        <li className="mb-6">
          <NavItem
            done={settings != null}
            title="1. Set Activity Category Standard"
            href="/getting-started/activity-standard"
            subtitle={settings?.[0].activity_category_standard?.name}
          />
        </li>
        <li className="mb-6">
          <NavItem
            done={numberOfRegions != null && numberOfRegions > 0}
            title="2. Upload Regions"
            href="/getting-started/upload-regions"
            subtitle={`${numberOfRegions} regions uploaded`}
          />
        </li>
        <li className="mb-6">
          <NavItem
            done={numberOfCustomSectors != null}
            title="3. Upload Custom Sectors (optional)"
            href="/getting-started/upload-custom-sectors"
            subtitle={`${numberOfCustomSectors} custom sectors uploaded`}
          />
        </li>
        <li className="mb-6">
          <NavItem
            done={numberOfCustomActivityCategoryCodes != null}
            title="4. Upload Custom Activity Category Standard Codes (optional)"
            href="/getting-started/upload-custom-activity-standard-codes"
            subtitle={`${numberOfCustomActivityCategoryCodes} custom activity category codes uploaded`}
          />
        </li>
        <li className="mb-6">
          <NavItem
            done={numberOfLegalUnits != null && numberOfLegalUnits > 0}
            title="5. Upload Legal Units"
            href="/getting-started/upload-legal-units"
            subtitle={`${numberOfLegalUnits} legal units uploaded`}
          />
        </li>
        <li className="mb-6">
          <NavItem
            done={numberOfEstablishments != null && numberOfEstablishments > 0}
            title="6. Upload Establishments"
            href="/getting-started/upload-establishments"
            subtitle={`${numberOfEstablishments} establishments uploaded`}
          />
        </li>
      </ul>
    </nav>
  );
}
