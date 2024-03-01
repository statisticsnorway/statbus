export type StatisticalUnitHierarchy = {
    enterprise: Enterprise;
};

export type Enterprise = {
    id: number;
    notes: string | null;
    active: boolean;
    legal_unit: LegalUnit[];
};

export type StatisticalUnit = {
    id: number;
    name: string;
    notes: string | null;
    active: boolean;
    primary: boolean;
    activity: any[];
    location: any[];
    valid_to: string;
    birth_date: string | null;
    death_date: string | null;
    reorg_date: string | null;
    short_name: string | null;
    stat_ident: string | null;
    valid_from: string;
    data_source: string | null;
    web_address: string | null;
    edit_comment: string;
    tax_reg_date: string;
    tax_reg_ident: string;
    telephone_no: string | null;
    unit_size_id: string | null;
    email_address: string | null;
    enterprise_id: number | null;
}

export type LegalUnit = StatisticalUnit & {
    establishment: Establishment[];
};

export type Establishment = StatisticalUnit & {
    invalid_codes: string | null;
    legal_unit_id: number;
    reorg_type_id: string | null;
    stat_for_unit: any[];
    tax_reg_ident: string;
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
    primary_for_legal_unit: boolean;
    data_source_classification_id: string | null;
};
