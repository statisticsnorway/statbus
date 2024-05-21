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
  id: number;
  valid_to: string;
  updated_at: string;
  valid_from: string;
  activity_type: string;
  legal_unit_id: number | null;
  establishment_id: number | null;
  activity_category: ActivityCategory;
  updated_by_user_id: number;
  activity_category_id: number;
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
  id: number;
  region: Region;
  country: Country;
  latitude: null;
  valid_to: string;
  longitude: null;
  region_id: number;
  country_id: number;
  valid_from: string;
  postal_code: string;
  postal_place: string;
  address_part1: string | null;
  address_part2: string | null;
  address_part3: string | null;
  legal_unit_id: number | null;
  location_type: string;
  establishment_id: number | null;
  updated_by_user_id: number;
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
  employees: number;
  turnover: number;
  valid_from: string;
  stat_definition: StatDefinition;
  establishment_id: number;
  stat_definition_id: number;
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
  web_address: string | null;
  edit_comment: string;
  telephone_no: string | null;
  unit_size_id: string | null;
  email_address: string | null;
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
  data_source_classification_id: string | null;
}

declare interface Enterprise extends StatisticalUnit {
  legal_unit: LegalUnit[];
  establishment: string | null;
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
}

declare interface Establishment extends StatisticalUnit {
  name: string;
  activity: Activity[];
  location: Location[];
  enterprise_id: string | null;
  legal_unit_id: number;
  primary_for_legal_unit: boolean;
  stat_for_unit?: StatForUnit[];
}

declare interface StatisticalUnitHierarchy {
  enterprise: Enterprise;
}
