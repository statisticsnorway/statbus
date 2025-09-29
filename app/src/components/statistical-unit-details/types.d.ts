type UnitType =
  | "enterprise"
  | "enterprise_group"
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