declare interface ActivityCategoryStandard {
  id: number;
  code: string;
  name: string;
  obsolete: boolean;
}

declare interface ActivityCategory {
  id: number;
  code: string;
  name: string;
  path: string;
  label: string;
  level: number;
  active: boolean;
  custom: boolean;
  parent_id: number;
  updated_at: string;
  description: string;
  activity_category_standard: ActivityCategoryStandard;
  activity_category_standard_id: number;
}

declare interface Activity {
  activity_category: ActivityCategory;
  category_id: number;
  data_source_id: number | null;
  edit_at: string;
  edit_by_user_id: number;
  edit_comment: string | null;
  establishment_id: number | null;
  id: number;
  legal_unit_id: number | null;
  type: string;
  valid_after: string;
  valid_from: string;
  valid_to: string;
}

declare interface LegalForm {
  active: boolean;
  code: string;
  created_at: string;
  custom: boolean;
  id: number;
  name: string;
  updated_at: string;
}

declare interface Sector {
  active: boolean;
  code: string | null;
  created_at: string;
  custom: boolean;
  description: string | null;
  id: number;
  label: string;
  name: string;
  parent_id: number | null;
  path: unknown;
  updated_at: string;
}

declare interface Region {
  id: number;
  code: string;
  name: string;
  path: string;
  label: string;
  level: number;
  parent_id: number;
}

declare interface Country {
  id: number;
  name: string;
  active: boolean;
  iso_2: string;
  iso_3: string;
  custom: boolean;
  iso_num: string;
  updated_at: string;
}

declare interface Location {
  address_part1: string | null;
  address_part2: string | null;
  address_part3: string | null;
  altitude: number | null;
  country: Country;
  country_id: number;
  data_source_id: number | null;
  edit_at: string;
  edit_by_user_id: number;
  edit_comment: string | null;
  establishment_id: number | null;
  id: number;
  latitude: number | null;
  legal_unit_id: number | null;
  longitude: number | null;
  postcode: string | null;
  postplace: string | null;
  region_id: number | null;
  region: Region;
  type: string;
  valid_after: string;
  valid_from: string;
  valid_to: string;
}

declare interface Contact {
  data_source_id: number | null;
  edit_at: string;
  edit_by_user_id: number;
  edit_comment: string | null;
  email_address: string | null;
  establishment_id: number | null;
  fax_number: string | null;
  id: number;
  landline: string | null;
  legal_unit_id: number | null;
  mobile_number: string | null;
  phone_number: string | null;
  valid_after: string;
  valid_from: string;
  valid_to: string;
  web_address: string | null;
}

declare interface StatDefinition {
  id: number;
  code: string;
  name: string;
  archived: boolean;
  priority: number;
  frequency: string;
  stat_type: string;
  description: string;
}

declare interface StatForUnit {
  id: number;
  valid_to: string;
  value_int: number | null;
  value_float: number | null;
  value_string: string | null;
  value_bool: boolean | null;
  valid_from: string;
  stat_definition: StatDefinition;
  establishment_id: number;
  stat_definition_id: number;
}

declare interface Status {
  active: boolean;
  assigned_by_default: boolean;
  code: string;
  created_at: string;
  custom: boolean;
  id: number;
  include_unit_in_reports: boolean;
  name: string;
  priority: number;
  updated_at: string;
}

declare interface StatisticalUnit {
  id: number;
  notes: string | null;
  active: boolean;
  valid_to: string;
  birth_date: string;
  death_date: string | null;
  reorg_date: string | null;
  short_name: string | null;
  stat_ident: string | null;
  valid_from: string;
  data_source: string | null;
  edit_comment: string;
  edit_at: string;
  unit_size_id: string | null;
  invalid_codes: string | null;
  reorg_type_id: string | null;
  tax_ident: string;
  external_ident: string | null;
  free_econ_zone: string | null;
  sector_code_id: string | null;
  edit_by_user_id: string;
  parent_org_link: string | null;
  stat_ident_date: string | null;
  reorg_references: string | null;
  seen_in_import_at: string;
  external_ident_date: string | null;
  external_ident_type: string | null;
  external_idents: Json;
  data_source_classification_id: string | null;
}

declare interface Enterprise extends StatisticalUnit {
  legal_unit: LegalUnit[];
  establishment: Establishment[];
}

declare interface LegalUnit extends StatisticalUnit {
  name: string;
  activity: Activity[];
  location: Location[];
  enterprise_id: number;
  establishment: Establishment[];
  legal_form_id: string | null;
  primary_for_enterprise: boolean;
  foreign_participation_id: string | null;
  stat_for_unit?: StatForUnit[];
  contact: Contact;
  legal_form: LegalForm;
  sector: Sector;
  status: Status;
}

declare interface Establishment extends StatisticalUnit {
  name: string;
  activity: Activity[];
  location: Location[];
  enterprise_id: string | null;
  legal_unit_id: number;
  primary_for_legal_unit: boolean;
  primary_for_enterprise: boolean;
  stat_for_unit?: StatForUnit[];
  contact: Contact;
  status: Status;
}

declare interface StatisticalUnitHierarchy {
  enterprise: Enterprise;
}

declare interface StatisticalUnitDetails {
  enterprise?: Enterprise;
  legal_unit?: LegalUnit[];
  establishment?: Establishment[];
}


declare interface StatisticalUnitStats {
  unit_type: StatisticalUnitType;
  unit_id: number;
  valid_from: string;
  valid_to: string;
  stats: { [key: string]: number | string };
  stats_summary: StatsSummary;
};

declare interface StatisticalUnitHistoryHighcharts {
  series: Array<{
    data: [number, number][];
    name: string;
  }>;
  unit_id: number;
  unit_name: string;
}