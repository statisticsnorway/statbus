type UnitType =
  | "enterprise"
  | "power_group"
  | "legal_unit"
  | "establishment";

interface Metadata {
  edit_by_user_id: number | null;
  edit_at: string | null;
  edit_comment: string | null;
  valid_from: string | null;
  valid_to: string | null;
  data_source_id: number | null;
}

interface UnitHistory {
  valid_from: string | null;
  name: string | null;
  physical_region: {
    code: string | null;
    name: string;
  } | null;
  primary_activity_category: {
    code: string;
    name: string;
  } | null;
  status: {
    code: string;
    name: string;
  } | null;
};
