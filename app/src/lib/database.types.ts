export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      activity: {
        Row: {
          category_id: number
          data_source_id: number | null
          edit_at: string
          edit_by_user_id: number
          edit_comment: string | null
          establishment_id: number | null
          id: number
          legal_unit_id: number | null
          type: Database["public"]["Enums"]["activity_type"]
          valid_after: string
          valid_from: string
          valid_to: string
        }
        Insert: {
          category_id: number
          data_source_id?: number | null
          edit_at?: string
          edit_by_user_id: number
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number
          legal_unit_id?: number | null
          type: Database["public"]["Enums"]["activity_type"]
          valid_after?: string
          valid_from?: string
          valid_to?: string
        }
        Update: {
          category_id?: number
          data_source_id?: number | null
          edit_at?: string
          edit_by_user_id?: number
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number
          legal_unit_id?: number | null
          type?: Database["public"]["Enums"]["activity_type"]
          valid_after?: string
          valid_from?: string
          valid_to?: string
        }
        Relationships: [
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
        ]
      }
      activity_category: {
        Row: {
          active: boolean
          code: string
          created_at: string
          custom: boolean
          description: string | null
          id: number
          label: string
          level: number | null
          name: string
          parent_id: number | null
          path: unknown
          standard_id: number
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          created_at?: string
          custom: boolean
          description?: string | null
          id?: never
          label?: string
          level?: number | null
          name: string
          parent_id?: number | null
          path: unknown
          standard_id: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          created_at?: string
          custom?: boolean
          description?: string | null
          id?: never
          label?: string
          level?: number | null
          name?: string
          parent_id?: number | null
          path?: unknown
          standard_id?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "activity_category_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "activity_category_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_standard_id_fkey"
            columns: ["standard_id"]
            isOneToOne: false
            referencedRelation: "activity_category_standard"
            referencedColumns: ["id"]
          },
        ]
      }
      activity_category_access: {
        Row: {
          activity_category_id: number
          id: number
          user_id: number
        }
        Insert: {
          activity_category_id: number
          id?: never
          user_id: number
        }
        Update: {
          activity_category_id?: number
          id?: never
          user_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "activity_category_access_activity_category_id_fkey"
            columns: ["activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_access_activity_category_id_fkey"
            columns: ["activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_access_activity_category_id_fkey"
            columns: ["activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_access_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
        ]
      }
      activity_category_standard: {
        Row: {
          code: string
          code_pattern: Database["public"]["Enums"]["activity_category_code_behaviour"]
          description: string
          id: number
          name: string
          obsolete: boolean
        }
        Insert: {
          code: string
          code_pattern: Database["public"]["Enums"]["activity_category_code_behaviour"]
          description: string
          id?: never
          name: string
          obsolete?: boolean
        }
        Update: {
          code?: string
          code_pattern?: Database["public"]["Enums"]["activity_category_code_behaviour"]
          description?: string
          id?: never
          name?: string
          obsolete?: boolean
        }
        Relationships: []
      }
      activity_category_used: {
        Row: {
          code: string | null
          description: string | null
          id: number | null
          label: string | null
          name: string | null
          parent_path: unknown | null
          path: unknown | null
          standard_code: string | null
        }
        Insert: {
          code?: string | null
          description?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_path?: unknown | null
          path?: unknown | null
          standard_code?: string | null
        }
        Update: {
          code?: string | null
          description?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_path?: unknown | null
          path?: unknown | null
          standard_code?: string | null
        }
        Relationships: []
      }
      contact: {
        Row: {
          data_source_id: number | null
          edit_at: string
          edit_by_user_id: number
          edit_comment: string | null
          email_address: string | null
          establishment_id: number | null
          fax_number: string | null
          id: number
          landline: string | null
          legal_unit_id: number | null
          mobile_number: string | null
          phone_number: string | null
          valid_after: string
          valid_from: string
          valid_to: string
          web_address: string | null
        }
        Insert: {
          data_source_id?: number | null
          edit_at?: string
          edit_by_user_id: number
          edit_comment?: string | null
          email_address?: string | null
          establishment_id?: number | null
          fax_number?: string | null
          id?: number
          landline?: string | null
          legal_unit_id?: number | null
          mobile_number?: string | null
          phone_number?: string | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
          web_address?: string | null
        }
        Update: {
          data_source_id?: number | null
          edit_at?: string
          edit_by_user_id?: number
          edit_comment?: string | null
          email_address?: string | null
          establishment_id?: number | null
          fax_number?: string | null
          id?: number
          landline?: string | null
          legal_unit_id?: number | null
          mobile_number?: string | null
          phone_number?: string | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contact_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contact_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contact_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contact_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contact_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
        ]
      }
      country: {
        Row: {
          active: boolean
          created_at: string
          custom: boolean
          id: number
          iso_2: string
          iso_3: string
          iso_num: string
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          created_at?: string
          custom: boolean
          id?: never
          iso_2: string
          iso_3: string
          iso_num: string
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          custom?: boolean
          id?: never
          iso_2?: string
          iso_3?: string
          iso_num?: string
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      country_used: {
        Row: {
          id: number | null
          iso_2: string | null
          name: string | null
        }
        Insert: {
          id?: number | null
          iso_2?: string | null
          name?: string | null
        }
        Update: {
          id?: number | null
          iso_2?: string | null
          name?: string | null
        }
        Relationships: []
      }
      data_source: {
        Row: {
          active: boolean
          code: string
          created_at: string
          custom: boolean
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          created_at?: string
          custom: boolean
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          created_at?: string
          custom?: boolean
          id?: never
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      data_source_used: {
        Row: {
          code: string | null
          id: number | null
          name: string | null
        }
        Insert: {
          code?: string | null
          id?: number | null
          name?: string | null
        }
        Update: {
          code?: string | null
          id?: number | null
          name?: string | null
        }
        Relationships: []
      }
      enterprise: {
        Row: {
          active: boolean
          edit_at: string
          edit_by_user_id: number
          edit_comment: string | null
          id: number
          short_name: string | null
        }
        Insert: {
          active?: boolean
          edit_at?: string
          edit_by_user_id: number
          edit_comment?: string | null
          id?: never
          short_name?: string | null
        }
        Update: {
          active?: boolean
          edit_at?: string
          edit_by_user_id?: number
          edit_comment?: string | null
          id?: never
          short_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "enterprise_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
        ]
      }
      enterprise_group: {
        Row: {
          active: boolean
          contact_person: string | null
          data_source_id: number | null
          edit_at: string
          edit_by_user_id: number
          edit_comment: string | null
          enterprise_group_type_id: number | null
          foreign_participation_id: number | null
          id: number
          name: string | null
          reorg_date: string | null
          reorg_references: string | null
          reorg_type_id: number | null
          short_name: string | null
          unit_size_id: number | null
          valid_after: string
          valid_from: string
          valid_to: string
        }
        Insert: {
          active?: boolean
          contact_person?: string | null
          data_source_id?: number | null
          edit_at?: string
          edit_by_user_id: number
          edit_comment?: string | null
          enterprise_group_type_id?: number | null
          foreign_participation_id?: number | null
          id?: number
          name?: string | null
          reorg_date?: string | null
          reorg_references?: string | null
          reorg_type_id?: number | null
          short_name?: string | null
          unit_size_id?: number | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
        }
        Update: {
          active?: boolean
          contact_person?: string | null
          data_source_id?: number | null
          edit_at?: string
          edit_by_user_id?: number
          edit_comment?: string | null
          enterprise_group_type_id?: number | null
          foreign_participation_id?: number | null
          id?: number
          name?: string | null
          reorg_date?: string | null
          reorg_references?: string | null
          reorg_type_id?: number | null
          short_name?: string | null
          unit_size_id?: number | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
        }
        Relationships: [
          {
            foreignKeyName: "enterprise_group_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_enterprise_group_type_id_fkey"
            columns: ["enterprise_group_type_id"]
            isOneToOne: false
            referencedRelation: "enterprise_group_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_enterprise_group_type_id_fkey"
            columns: ["enterprise_group_type_id"]
            isOneToOne: false
            referencedRelation: "enterprise_group_type_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_enterprise_group_type_id_fkey"
            columns: ["enterprise_group_type_id"]
            isOneToOne: false
            referencedRelation: "enterprise_group_type_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_ordered"
            referencedColumns: ["id"]
          },
        ]
      }
      enterprise_group_role: {
        Row: {
          active: boolean
          code: string
          created_at: string
          custom: boolean
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          created_at?: string
          custom: boolean
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          created_at?: string
          custom?: boolean
          id?: never
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      enterprise_group_type: {
        Row: {
          active: boolean
          code: string
          created_at: string
          custom: boolean
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          created_at?: string
          custom: boolean
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          created_at?: string
          custom?: boolean
          id?: never
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      establishment: {
        Row: {
          active: boolean
          birth_date: string | null
          data_source_id: number | null
          death_date: string | null
          edit_at: string
          edit_by_user_id: number
          edit_comment: string | null
          enterprise_id: number | null
          free_econ_zone: boolean | null
          id: number
          invalid_codes: Json | null
          legal_unit_id: number | null
          name: string | null
          primary_for_enterprise: boolean | null
          primary_for_legal_unit: boolean | null
          sector_id: number | null
          short_name: string | null
          status_id: number | null
          unit_size_id: number | null
          valid_after: string
          valid_from: string
          valid_to: string
        }
        Insert: {
          active?: boolean
          birth_date?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_at?: string
          edit_by_user_id: number
          edit_comment?: string | null
          enterprise_id?: number | null
          free_econ_zone?: boolean | null
          id?: number
          invalid_codes?: Json | null
          legal_unit_id?: number | null
          name?: string | null
          primary_for_enterprise?: boolean | null
          primary_for_legal_unit?: boolean | null
          sector_id?: number | null
          short_name?: string | null
          status_id?: number | null
          unit_size_id?: number | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
        }
        Update: {
          active?: boolean
          birth_date?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_at?: string
          edit_by_user_id?: number
          edit_comment?: string | null
          enterprise_id?: number | null
          free_econ_zone?: boolean | null
          id?: number
          invalid_codes?: Json | null
          legal_unit_id?: number | null
          name?: string | null
          primary_for_enterprise?: boolean | null
          primary_for_legal_unit?: boolean | null
          sector_id?: number | null
          short_name?: string | null
          status_id?: number | null
          unit_size_id?: number | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
        }
        Relationships: [
          {
            foreignKeyName: "establishment_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "enterprise"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise_def"
            referencedColumns: ["enterprise_id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "establishment_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "status"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_ordered"
            referencedColumns: ["id"]
          },
        ]
      }
      external_ident: {
        Row: {
          edit_at: string
          edit_by_user_id: number
          edit_comment: string | null
          enterprise_group_id: number | null
          enterprise_id: number | null
          establishment_id: number | null
          id: number
          ident: string
          legal_unit_id: number | null
          type_id: number
        }
        Insert: {
          edit_at?: string
          edit_by_user_id: number
          edit_comment?: string | null
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: number
          ident: string
          legal_unit_id?: number | null
          type_id: number
        }
        Update: {
          edit_at?: string
          edit_by_user_id?: number
          edit_comment?: string | null
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: number
          ident?: string
          legal_unit_id?: number | null
          type_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "external_ident_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_ident_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "enterprise"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_ident_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise_def"
            referencedColumns: ["enterprise_id"]
          },
          {
            foreignKeyName: "external_ident_type_id_fkey"
            columns: ["type_id"]
            isOneToOne: false
            referencedRelation: "external_ident_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_ident_type_id_fkey"
            columns: ["type_id"]
            isOneToOne: false
            referencedRelation: "external_ident_type_active"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_ident_type_id_fkey"
            columns: ["type_id"]
            isOneToOne: false
            referencedRelation: "external_ident_type_ordered"
            referencedColumns: ["id"]
          },
        ]
      }
      external_ident_type: {
        Row: {
          archived: boolean
          by_tag_id: number | null
          code: string
          description: string | null
          id: number
          name: string | null
          priority: number | null
        }
        Insert: {
          archived?: boolean
          by_tag_id?: number | null
          code: string
          description?: string | null
          id?: never
          name?: string | null
          priority?: number | null
        }
        Update: {
          archived?: boolean
          by_tag_id?: number | null
          code?: string
          description?: string | null
          id?: never
          name?: string | null
          priority?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "external_ident_type_by_tag_id_fkey"
            columns: ["by_tag_id"]
            isOneToOne: true
            referencedRelation: "tag"
            referencedColumns: ["id"]
          },
        ]
      }
      foreign_participation: {
        Row: {
          active: boolean
          code: string
          created_at: string
          custom: boolean
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          created_at?: string
          custom: boolean
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          created_at?: string
          custom?: boolean
          id?: never
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      import_definition: {
        Row: {
          created_at: string
          data_source_id: number | null
          draft: boolean
          id: number
          name: string
          note: string | null
          slug: string
          target_id: number | null
          time_context_ident: string | null
          updated_at: string
          user_id: number | null
          valid: boolean
          validation_error: string | null
        }
        Insert: {
          created_at?: string
          data_source_id?: number | null
          draft?: boolean
          id?: never
          name: string
          note?: string | null
          slug: string
          target_id?: number | null
          time_context_ident?: string | null
          updated_at?: string
          user_id?: number | null
          valid?: boolean
          validation_error?: string | null
        }
        Update: {
          created_at?: string
          data_source_id?: number | null
          draft?: boolean
          id?: never
          name?: string
          note?: string | null
          slug?: string
          target_id?: number | null
          time_context_ident?: string | null
          updated_at?: string
          user_id?: number | null
          valid?: boolean
          validation_error?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "import_definition_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "import_definition_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "import_definition_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "import_definition_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "import_definition_target_id_fkey"
            columns: ["target_id"]
            isOneToOne: false
            referencedRelation: "import_target"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "import_definition_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
        ]
      }
      import_job: {
        Row: {
          analysis_start_at: string | null
          analysis_stop_at: string | null
          changes_approved_at: string | null
          changes_rejected_at: string | null
          data_table_name: string
          default_data_source_code: string | null
          default_valid_from: string | null
          default_valid_to: string | null
          definition_id: number
          description: string | null
          error: string | null
          id: number
          import_completed_pct: number | null
          import_information_snapshot_table_name: string
          import_rows_per_sec: number | null
          import_start_at: string | null
          import_stop_at: string | null
          imported_rows: number | null
          last_progress_update: string | null
          note: string | null
          preparing_data_at: string | null
          priority: number | null
          review: boolean
          slug: string
          state: Database["public"]["Enums"]["import_job_state"]
          target_schema_name: string
          target_table_name: string
          total_rows: number | null
          upload_table_name: string
          user_id: number | null
        }
        Insert: {
          analysis_start_at?: string | null
          analysis_stop_at?: string | null
          changes_approved_at?: string | null
          changes_rejected_at?: string | null
          data_table_name: string
          default_data_source_code?: string | null
          default_valid_from?: string | null
          default_valid_to?: string | null
          definition_id: number
          description?: string | null
          error?: string | null
          id?: never
          import_completed_pct?: number | null
          import_information_snapshot_table_name: string
          import_rows_per_sec?: number | null
          import_start_at?: string | null
          import_stop_at?: string | null
          imported_rows?: number | null
          last_progress_update?: string | null
          note?: string | null
          preparing_data_at?: string | null
          priority?: number | null
          review?: boolean
          slug: string
          state?: Database["public"]["Enums"]["import_job_state"]
          target_schema_name: string
          target_table_name: string
          total_rows?: number | null
          upload_table_name: string
          user_id?: number | null
        }
        Update: {
          analysis_start_at?: string | null
          analysis_stop_at?: string | null
          changes_approved_at?: string | null
          changes_rejected_at?: string | null
          data_table_name?: string
          default_data_source_code?: string | null
          default_valid_from?: string | null
          default_valid_to?: string | null
          definition_id?: number
          description?: string | null
          error?: string | null
          id?: never
          import_completed_pct?: number | null
          import_information_snapshot_table_name?: string
          import_rows_per_sec?: number | null
          import_start_at?: string | null
          import_stop_at?: string | null
          imported_rows?: number | null
          last_progress_update?: string | null
          note?: string | null
          preparing_data_at?: string | null
          priority?: number | null
          review?: boolean
          slug?: string
          state?: Database["public"]["Enums"]["import_job_state"]
          target_schema_name?: string
          target_table_name?: string
          total_rows?: number | null
          upload_table_name?: string
          user_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "import_job_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "import_definition"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "import_job_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "import_information"
            referencedColumns: ["definition_id"]
          },
          {
            foreignKeyName: "import_job_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
        ]
      }
      import_mapping: {
        Row: {
          created_at: string
          definition_id: number
          source_column_id: number | null
          source_expression:
            | Database["public"]["Enums"]["import_source_expression"]
            | null
          source_value: string | null
          target_column_id: number | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          definition_id: number
          source_column_id?: number | null
          source_expression?:
            | Database["public"]["Enums"]["import_source_expression"]
            | null
          source_value?: string | null
          target_column_id?: number | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          definition_id?: number
          source_column_id?: number | null
          source_expression?:
            | Database["public"]["Enums"]["import_source_expression"]
            | null
          source_value?: string | null
          target_column_id?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "import_mapping_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "import_definition"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "import_mapping_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "import_information"
            referencedColumns: ["definition_id"]
          },
          {
            foreignKeyName: "import_mapping_source_column_id_fkey"
            columns: ["source_column_id"]
            isOneToOne: false
            referencedRelation: "import_source_column"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "import_mapping_target_column_id_fkey"
            columns: ["target_column_id"]
            isOneToOne: false
            referencedRelation: "import_target_column"
            referencedColumns: ["id"]
          },
        ]
      }
      import_source_column: {
        Row: {
          column_name: string
          created_at: string
          definition_id: number | null
          id: number
          priority: number
          updated_at: string
        }
        Insert: {
          column_name: string
          created_at?: string
          definition_id?: number | null
          id?: never
          priority: number
          updated_at?: string
        }
        Update: {
          column_name?: string
          created_at?: string
          definition_id?: number | null
          id?: never
          priority?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "import_source_column_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "import_definition"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "import_source_column_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "import_information"
            referencedColumns: ["definition_id"]
          },
        ]
      }
      import_target: {
        Row: {
          created_at: string
          id: number
          name: string
          schema_name: string
          table_name: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: never
          name: string
          schema_name: string
          table_name?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: never
          name?: string
          schema_name?: string
          table_name?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      import_target_column: {
        Row: {
          column_name: string
          column_type: string
          created_at: string
          id: number
          target_id: number | null
          uniquely_identifying: boolean
          updated_at: string
        }
        Insert: {
          column_name: string
          column_type: string
          created_at?: string
          id?: never
          target_id?: number | null
          uniquely_identifying: boolean
          updated_at?: string
        }
        Update: {
          column_name?: string
          column_type?: string
          created_at?: string
          id?: never
          target_id?: number | null
          uniquely_identifying?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "import_target_column_target_id_fkey"
            columns: ["target_id"]
            isOneToOne: false
            referencedRelation: "import_target"
            referencedColumns: ["id"]
          },
        ]
      }
      legal_form: {
        Row: {
          active: boolean
          code: string
          created_at: string
          custom: boolean
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          created_at?: string
          custom: boolean
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          created_at?: string
          custom?: boolean
          id?: never
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      legal_form_used: {
        Row: {
          code: string | null
          id: number | null
          name: string | null
        }
        Insert: {
          code?: string | null
          id?: number | null
          name?: string | null
        }
        Update: {
          code?: string | null
          id?: number | null
          name?: string | null
        }
        Relationships: []
      }
      legal_unit: {
        Row: {
          active: boolean
          birth_date: string | null
          data_source_id: number | null
          death_date: string | null
          edit_at: string
          edit_by_user_id: number
          edit_comment: string | null
          enterprise_id: number
          foreign_participation_id: number | null
          free_econ_zone: boolean | null
          id: number
          invalid_codes: Json | null
          legal_form_id: number | null
          name: string | null
          primary_for_enterprise: boolean
          sector_id: number | null
          short_name: string | null
          status_id: number | null
          unit_size_id: number | null
          valid_after: string
          valid_from: string
          valid_to: string
        }
        Insert: {
          active?: boolean
          birth_date?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_at?: string
          edit_by_user_id: number
          edit_comment?: string | null
          enterprise_id: number
          foreign_participation_id?: number | null
          free_econ_zone?: boolean | null
          id?: number
          invalid_codes?: Json | null
          legal_form_id?: number | null
          name?: string | null
          primary_for_enterprise: boolean
          sector_id?: number | null
          short_name?: string | null
          status_id?: number | null
          unit_size_id?: number | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
        }
        Update: {
          active?: boolean
          birth_date?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_at?: string
          edit_by_user_id?: number
          edit_comment?: string | null
          enterprise_id?: number
          foreign_participation_id?: number | null
          free_econ_zone?: boolean | null
          id?: number
          invalid_codes?: Json | null
          legal_form_id?: number | null
          name?: string | null
          primary_for_enterprise?: boolean
          sector_id?: number | null
          short_name?: string | null
          status_id?: number | null
          unit_size_id?: number | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
        }
        Relationships: [
          {
            foreignKeyName: "legal_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "enterprise"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise_def"
            referencedColumns: ["enterprise_id"]
          },
          {
            foreignKeyName: "legal_unit_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["legal_form_id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "legal_unit_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "status"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_ordered"
            referencedColumns: ["id"]
          },
        ]
      }
      location: {
        Row: {
          address_part1: string | null
          address_part2: string | null
          address_part3: string | null
          altitude: number | null
          country_id: number
          data_source_id: number | null
          edit_at: string
          edit_by_user_id: number
          edit_comment: string | null
          establishment_id: number | null
          id: number
          latitude: number | null
          legal_unit_id: number | null
          longitude: number | null
          postcode: string | null
          postplace: string | null
          region_id: number | null
          type: Database["public"]["Enums"]["location_type"]
          valid_after: string
          valid_from: string
          valid_to: string
        }
        Insert: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          altitude?: number | null
          country_id: number
          data_source_id?: number | null
          edit_at?: string
          edit_by_user_id: number
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number
          latitude?: number | null
          legal_unit_id?: number | null
          longitude?: number | null
          postcode?: string | null
          postplace?: string | null
          region_id?: number | null
          type: Database["public"]["Enums"]["location_type"]
          valid_after?: string
          valid_from?: string
          valid_to?: string
        }
        Update: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          altitude?: number | null
          country_id?: number
          data_source_id?: number | null
          edit_at?: string
          edit_by_user_id?: number
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number
          latitude?: number | null
          legal_unit_id?: number | null
          longitude?: number | null
          postcode?: string | null
          postplace?: string | null
          region_id?: number | null
          type?: Database["public"]["Enums"]["location_type"]
          valid_after?: string
          valid_from?: string
          valid_to?: string
        }
        Relationships: [
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country_view"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "region"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "region_used_def"
            referencedColumns: ["id"]
          },
        ]
      }
      person: {
        Row: {
          address_part1: string | null
          address_part2: string | null
          address_part3: string | null
          birth_date: string | null
          country_id: number | null
          created_at: string
          family_name: string | null
          given_name: string | null
          id: number
          middle_name: string | null
          mobile_number: string | null
          personal_ident: string | null
          phone_number: string | null
          sex: Database["public"]["Enums"]["person_sex"] | null
        }
        Insert: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          birth_date?: string | null
          country_id?: number | null
          created_at?: string
          family_name?: string | null
          given_name?: string | null
          id?: never
          middle_name?: string | null
          mobile_number?: string | null
          personal_ident?: string | null
          phone_number?: string | null
          sex?: Database["public"]["Enums"]["person_sex"] | null
        }
        Update: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          birth_date?: string | null
          country_id?: number | null
          created_at?: string
          family_name?: string | null
          given_name?: string | null
          id?: never
          middle_name?: string | null
          mobile_number?: string | null
          personal_ident?: string | null
          phone_number?: string | null
          sex?: Database["public"]["Enums"]["person_sex"] | null
        }
        Relationships: [
          {
            foreignKeyName: "person_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country_view"
            referencedColumns: ["id"]
          },
        ]
      }
      person_for_unit: {
        Row: {
          data_source_id: number | null
          establishment_id: number | null
          id: number
          legal_unit_id: number | null
          person_id: number
          person_role_id: number | null
          valid_after: string
          valid_from: string
          valid_to: string
        }
        Insert: {
          data_source_id?: number | null
          establishment_id?: number | null
          id?: never
          legal_unit_id?: number | null
          person_id: number
          person_role_id?: number | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
        }
        Update: {
          data_source_id?: number | null
          establishment_id?: number | null
          id?: never
          legal_unit_id?: number | null
          person_id?: number
          person_role_id?: number | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
        }
        Relationships: [
          {
            foreignKeyName: "person_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_for_unit_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "person"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_for_unit_person_role_id_fkey"
            columns: ["person_role_id"]
            isOneToOne: false
            referencedRelation: "person_role"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_for_unit_person_role_id_fkey"
            columns: ["person_role_id"]
            isOneToOne: false
            referencedRelation: "person_role_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_for_unit_person_role_id_fkey"
            columns: ["person_role_id"]
            isOneToOne: false
            referencedRelation: "person_role_ordered"
            referencedColumns: ["id"]
          },
        ]
      }
      person_role: {
        Row: {
          active: boolean
          code: string
          created_at: string
          custom: boolean
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          created_at?: string
          custom: boolean
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          created_at?: string
          custom?: boolean
          id?: never
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      region: {
        Row: {
          center_altitude: number | null
          center_latitude: number | null
          center_longitude: number | null
          code: string | null
          id: number
          label: string
          level: number | null
          name: string
          parent_id: number | null
          path: unknown
        }
        Insert: {
          center_altitude?: number | null
          center_latitude?: number | null
          center_longitude?: number | null
          code?: string | null
          id?: number
          label?: string
          level?: number | null
          name: string
          parent_id?: number | null
          path: unknown
        }
        Update: {
          center_altitude?: number | null
          center_latitude?: number | null
          center_longitude?: number | null
          code?: string | null
          id?: number
          label?: string
          level?: number | null
          name?: string
          parent_id?: number | null
          path?: unknown
        }
        Relationships: [
          {
            foreignKeyName: "region_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "region"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "region_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "region_used_def"
            referencedColumns: ["id"]
          },
        ]
      }
      region_access: {
        Row: {
          id: number
          region_id: number
          user_id: number
        }
        Insert: {
          id?: never
          region_id: number
          user_id: number
        }
        Update: {
          id?: never
          region_id?: number
          user_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "region_access_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "region"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "region_access_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "region_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "region_access_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
        ]
      }
      region_used: {
        Row: {
          code: string | null
          id: number | null
          label: string | null
          level: number | null
          name: string | null
          path: unknown | null
        }
        Insert: {
          code?: string | null
          id?: number | null
          label?: string | null
          level?: number | null
          name?: string | null
          path?: unknown | null
        }
        Update: {
          code?: string | null
          id?: number | null
          label?: string | null
          level?: number | null
          name?: string | null
          path?: unknown | null
        }
        Relationships: []
      }
      relative_period: {
        Row: {
          active: boolean
          code: Database["public"]["Enums"]["relative_period_code"]
          id: number
          name_when_input: string | null
          name_when_query: string | null
          scope: Database["public"]["Enums"]["relative_period_scope"]
        }
        Insert: {
          active?: boolean
          code: Database["public"]["Enums"]["relative_period_code"]
          id?: never
          name_when_input?: string | null
          name_when_query?: string | null
          scope: Database["public"]["Enums"]["relative_period_scope"]
        }
        Update: {
          active?: boolean
          code?: Database["public"]["Enums"]["relative_period_code"]
          id?: never
          name_when_input?: string | null
          name_when_query?: string | null
          scope?: Database["public"]["Enums"]["relative_period_scope"]
        }
        Relationships: []
      }
      reorg_type: {
        Row: {
          active: boolean
          code: string
          created_at: string
          custom: boolean
          description: string
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          created_at?: string
          custom: boolean
          description: string
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          created_at?: string
          custom?: boolean
          description?: string
          id?: never
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      sector: {
        Row: {
          active: boolean
          code: string | null
          created_at: string
          custom: boolean
          description: string | null
          id: number
          label: string
          name: string
          parent_id: number | null
          path: unknown
          updated_at: string
        }
        Insert: {
          active: boolean
          code?: string | null
          created_at?: string
          custom: boolean
          description?: string | null
          id?: never
          label?: string
          name: string
          parent_id?: number | null
          path: unknown
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string | null
          created_at?: string
          custom?: boolean
          description?: string | null
          id?: never
          label?: string
          name?: string
          parent_id?: number | null
          path?: unknown
          updated_at?: string
        }
        Relationships: []
      }
      sector_used: {
        Row: {
          code: string | null
          id: number | null
          label: string | null
          name: string | null
          path: unknown | null
        }
        Insert: {
          code?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          path?: unknown | null
        }
        Update: {
          code?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          path?: unknown | null
        }
        Relationships: []
      }
      settings: {
        Row: {
          activity_category_standard_id: number
          id: number
          only_one_setting: boolean
        }
        Insert: {
          activity_category_standard_id: number
          id?: never
          only_one_setting?: boolean
        }
        Update: {
          activity_category_standard_id?: number
          id?: never
          only_one_setting?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "settings_activity_category_standard_id_fkey"
            columns: ["activity_category_standard_id"]
            isOneToOne: false
            referencedRelation: "activity_category_standard"
            referencedColumns: ["id"]
          },
        ]
      }
      stat_definition: {
        Row: {
          archived: boolean
          code: string
          description: string | null
          frequency: Database["public"]["Enums"]["stat_frequency"]
          id: number
          name: string
          priority: number | null
          type: Database["public"]["Enums"]["stat_type"]
        }
        Insert: {
          archived?: boolean
          code: string
          description?: string | null
          frequency: Database["public"]["Enums"]["stat_frequency"]
          id?: number
          name: string
          priority?: number | null
          type: Database["public"]["Enums"]["stat_type"]
        }
        Update: {
          archived?: boolean
          code?: string
          description?: string | null
          frequency?: Database["public"]["Enums"]["stat_frequency"]
          id?: number
          name?: string
          priority?: number | null
          type?: Database["public"]["Enums"]["stat_type"]
        }
        Relationships: []
      }
      stat_for_unit: {
        Row: {
          data_source_id: number | null
          establishment_id: number | null
          id: number
          legal_unit_id: number | null
          stat_definition_id: number
          valid_after: string
          valid_from: string
          valid_to: string
          value_bool: boolean | null
          value_float: number | null
          value_int: number | null
          value_string: string | null
        }
        Insert: {
          data_source_id?: number | null
          establishment_id?: number | null
          id?: number
          legal_unit_id?: number | null
          stat_definition_id: number
          valid_after?: string
          valid_from?: string
          valid_to?: string
          value_bool?: boolean | null
          value_float?: number | null
          value_int?: number | null
          value_string?: string | null
        }
        Update: {
          data_source_id?: number | null
          establishment_id?: number | null
          id?: number
          legal_unit_id?: number | null
          stat_definition_id?: number
          valid_after?: string
          valid_from?: string
          valid_to?: string
          value_bool?: boolean | null
          value_float?: number | null
          value_int?: number | null
          value_string?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "stat_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_stat_definition_id_fkey"
            columns: ["stat_definition_id"]
            isOneToOne: false
            referencedRelation: "stat_definition"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_stat_definition_id_fkey"
            columns: ["stat_definition_id"]
            isOneToOne: false
            referencedRelation: "stat_definition_active"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_stat_definition_id_fkey"
            columns: ["stat_definition_id"]
            isOneToOne: false
            referencedRelation: "stat_definition_ordered"
            referencedColumns: ["id"]
          },
        ]
      }
      statistical_history: {
        Row: {
          births: number | null
          count: number | null
          deaths: number | null
          legal_form_change_count: number | null
          month: number | null
          name_change_count: number | null
          physical_address_change_count: number | null
          physical_country_change_count: number | null
          physical_region_change_count: number | null
          primary_activity_category_change_count: number | null
          resolution: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count: number | null
          sector_change_count: number | null
          stats_summary: Json | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          year: number | null
        }
        Insert: {
          births?: number | null
          count?: number | null
          deaths?: number | null
          legal_form_change_count?: number | null
          month?: number | null
          name_change_count?: number | null
          physical_address_change_count?: number | null
          physical_country_change_count?: number | null
          physical_region_change_count?: number | null
          primary_activity_category_change_count?: number | null
          resolution?: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count?: number | null
          sector_change_count?: number | null
          stats_summary?: Json | null
          unit_type?:
            | Database["public"]["Enums"]["statistical_unit_type"]
            | null
          year?: number | null
        }
        Update: {
          births?: number | null
          count?: number | null
          deaths?: number | null
          legal_form_change_count?: number | null
          month?: number | null
          name_change_count?: number | null
          physical_address_change_count?: number | null
          physical_country_change_count?: number | null
          physical_region_change_count?: number | null
          primary_activity_category_change_count?: number | null
          resolution?: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count?: number | null
          sector_change_count?: number | null
          stats_summary?: Json | null
          unit_type?:
            | Database["public"]["Enums"]["statistical_unit_type"]
            | null
          year?: number | null
        }
        Relationships: []
      }
      statistical_history_facet: {
        Row: {
          births: number | null
          count: number | null
          deaths: number | null
          legal_form_change_count: number | null
          legal_form_id: number | null
          month: number | null
          name_change_count: number | null
          physical_address_change_count: number | null
          physical_country_change_count: number | null
          physical_country_id: number | null
          physical_region_change_count: number | null
          physical_region_path: unknown | null
          primary_activity_category_change_count: number | null
          primary_activity_category_path: unknown | null
          resolution: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count: number | null
          secondary_activity_category_path: unknown | null
          sector_change_count: number | null
          sector_path: unknown | null
          stats_summary: Json | null
          status_change_count: number | null
          status_id: number | null
          unit_size_change_count: number | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          year: number | null
        }
        Insert: {
          births?: number | null
          count?: number | null
          deaths?: number | null
          legal_form_change_count?: number | null
          legal_form_id?: number | null
          month?: number | null
          name_change_count?: number | null
          physical_address_change_count?: number | null
          physical_country_change_count?: number | null
          physical_country_id?: number | null
          physical_region_change_count?: number | null
          physical_region_path?: unknown | null
          primary_activity_category_change_count?: number | null
          primary_activity_category_path?: unknown | null
          resolution?: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count?: number | null
          secondary_activity_category_path?: unknown | null
          sector_change_count?: number | null
          sector_path?: unknown | null
          stats_summary?: Json | null
          status_change_count?: number | null
          status_id?: number | null
          unit_size_change_count?: number | null
          unit_size_id?: number | null
          unit_type?:
            | Database["public"]["Enums"]["statistical_unit_type"]
            | null
          year?: number | null
        }
        Update: {
          births?: number | null
          count?: number | null
          deaths?: number | null
          legal_form_change_count?: number | null
          legal_form_id?: number | null
          month?: number | null
          name_change_count?: number | null
          physical_address_change_count?: number | null
          physical_country_change_count?: number | null
          physical_country_id?: number | null
          physical_region_change_count?: number | null
          physical_region_path?: unknown | null
          primary_activity_category_change_count?: number | null
          primary_activity_category_path?: unknown | null
          resolution?: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count?: number | null
          secondary_activity_category_path?: unknown | null
          sector_change_count?: number | null
          sector_path?: unknown | null
          stats_summary?: Json | null
          status_change_count?: number | null
          status_id?: number | null
          unit_size_change_count?: number | null
          unit_size_id?: number | null
          unit_type?:
            | Database["public"]["Enums"]["statistical_unit_type"]
            | null
          year?: number | null
        }
        Relationships: []
      }
      statistical_unit: {
        Row: {
          activity_category_paths: unknown[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          email_address: string | null
          excluded_enterprise_ids: number[] | null
          excluded_establishment_ids: number[] | null
          excluded_legal_unit_ids: number[] | null
          external_idents: Json | null
          fax_number: string | null
          has_legal_unit: boolean | null
          include_unit_in_reports: boolean | null
          included_enterprise_count: number | null
          included_enterprise_ids: number[] | null
          included_establishment_count: number | null
          included_establishment_ids: number[] | null
          included_legal_unit_count: number | null
          included_legal_unit_ids: number[] | null
          invalid_codes: Json | null
          landline: string | null
          last_edit_at: string | null
          last_edit_by_user_id: number | null
          last_edit_comment: string | null
          legal_form_code: string | null
          legal_form_id: number | null
          legal_form_name: string | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: number | null
          physical_country_id: number | null
          physical_country_iso_2: string | null
          physical_latitude: number | null
          physical_longitude: number | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_id: number | null
          physical_region_path: unknown | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: number | null
          postal_country_id: number | null
          postal_country_iso_2: string | null
          postal_latitude: number | null
          postal_longitude: number | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_id: number | null
          postal_region_path: unknown | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: unknown | null
          related_enterprise_ids: number[] | null
          related_establishment_ids: number[] | null
          related_legal_unit_ids: number[] | null
          search: unknown | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: unknown | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: unknown | null
          stats: Json | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          tag_paths: unknown[] | null
          unit_id: number | null
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
          web_address: string | null
        }
        Insert: {
          activity_category_paths?: unknown[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          email_address?: string | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          external_idents?: Json | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          include_unit_in_reports?: boolean | null
          included_enterprise_count?: number | null
          included_enterprise_ids?: number[] | null
          included_establishment_count?: number | null
          included_establishment_ids?: number[] | null
          included_legal_unit_count?: number | null
          included_legal_unit_ids?: number[] | null
          invalid_codes?: Json | null
          landline?: string | null
          last_edit_at?: string | null
          last_edit_by_user_id?: number | null
          last_edit_comment?: string | null
          legal_form_code?: string | null
          legal_form_id?: number | null
          legal_form_name?: string | null
          mobile_number?: string | null
          name?: string | null
          phone_number?: string | null
          physical_address_part1?: string | null
          physical_address_part2?: string | null
          physical_address_part3?: string | null
          physical_altitude?: number | null
          physical_country_id?: number | null
          physical_country_iso_2?: string | null
          physical_latitude?: number | null
          physical_longitude?: number | null
          physical_postcode?: string | null
          physical_postplace?: string | null
          physical_region_code?: string | null
          physical_region_id?: number | null
          physical_region_path?: unknown | null
          postal_address_part1?: string | null
          postal_address_part2?: string | null
          postal_address_part3?: string | null
          postal_altitude?: number | null
          postal_country_id?: number | null
          postal_country_iso_2?: string | null
          postal_latitude?: number | null
          postal_longitude?: number | null
          postal_postcode?: string | null
          postal_postplace?: string | null
          postal_region_code?: string | null
          postal_region_id?: number | null
          postal_region_path?: unknown | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: unknown | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: unknown | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: unknown | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: unknown | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          tag_paths?: unknown[] | null
          unit_id?: number | null
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?:
            | Database["public"]["Enums"]["statistical_unit_type"]
            | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
          web_address?: string | null
        }
        Update: {
          activity_category_paths?: unknown[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          email_address?: string | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          external_idents?: Json | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          include_unit_in_reports?: boolean | null
          included_enterprise_count?: number | null
          included_enterprise_ids?: number[] | null
          included_establishment_count?: number | null
          included_establishment_ids?: number[] | null
          included_legal_unit_count?: number | null
          included_legal_unit_ids?: number[] | null
          invalid_codes?: Json | null
          landline?: string | null
          last_edit_at?: string | null
          last_edit_by_user_id?: number | null
          last_edit_comment?: string | null
          legal_form_code?: string | null
          legal_form_id?: number | null
          legal_form_name?: string | null
          mobile_number?: string | null
          name?: string | null
          phone_number?: string | null
          physical_address_part1?: string | null
          physical_address_part2?: string | null
          physical_address_part3?: string | null
          physical_altitude?: number | null
          physical_country_id?: number | null
          physical_country_iso_2?: string | null
          physical_latitude?: number | null
          physical_longitude?: number | null
          physical_postcode?: string | null
          physical_postplace?: string | null
          physical_region_code?: string | null
          physical_region_id?: number | null
          physical_region_path?: unknown | null
          postal_address_part1?: string | null
          postal_address_part2?: string | null
          postal_address_part3?: string | null
          postal_altitude?: number | null
          postal_country_id?: number | null
          postal_country_iso_2?: string | null
          postal_latitude?: number | null
          postal_longitude?: number | null
          postal_postcode?: string | null
          postal_postplace?: string | null
          postal_region_code?: string | null
          postal_region_id?: number | null
          postal_region_path?: unknown | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: unknown | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: unknown | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: unknown | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: unknown | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          tag_paths?: unknown[] | null
          unit_id?: number | null
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?:
            | Database["public"]["Enums"]["statistical_unit_type"]
            | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
          web_address?: string | null
        }
        Relationships: []
      }
      statistical_unit_facet: {
        Row: {
          count: number | null
          legal_form_id: number | null
          physical_country_id: number | null
          physical_region_path: unknown | null
          primary_activity_category_path: unknown | null
          sector_path: unknown | null
          stats_summary: Json | null
          status_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from: string | null
          valid_to: string | null
        }
        Insert: {
          count?: number | null
          legal_form_id?: number | null
          physical_country_id?: number | null
          physical_region_path?: unknown | null
          primary_activity_category_path?: unknown | null
          sector_path?: unknown | null
          stats_summary?: Json | null
          status_id?: number | null
          unit_type?:
            | Database["public"]["Enums"]["statistical_unit_type"]
            | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Update: {
          count?: number | null
          legal_form_id?: number | null
          physical_country_id?: number | null
          physical_region_path?: unknown | null
          primary_activity_category_path?: unknown | null
          sector_path?: unknown | null
          stats_summary?: Json | null
          status_id?: number | null
          unit_type?:
            | Database["public"]["Enums"]["statistical_unit_type"]
            | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Relationships: []
      }
      status: {
        Row: {
          active: boolean
          assigned_by_default: boolean
          code: string
          created_at: string
          custom: boolean
          id: number
          include_unit_in_reports: boolean
          name: string
          priority: number
          updated_at: string
        }
        Insert: {
          active: boolean
          assigned_by_default: boolean
          code: string
          created_at?: string
          custom?: boolean
          id?: never
          include_unit_in_reports: boolean
          name: string
          priority: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          assigned_by_default?: boolean
          code?: string
          created_at?: string
          custom?: boolean
          id?: never
          include_unit_in_reports?: boolean
          name?: string
          priority?: number
          updated_at?: string
        }
        Relationships: []
      }
      tag: {
        Row: {
          active: boolean
          code: string | null
          context_valid_after: string | null
          context_valid_from: string | null
          context_valid_on: string | null
          context_valid_to: string | null
          created_at: string
          description: string | null
          id: number
          is_scoped_tag: boolean
          label: string
          level: number | null
          name: string
          parent_id: number | null
          path: unknown
          type: Database["public"]["Enums"]["tag_type"]
          updated_at: string
        }
        Insert: {
          active?: boolean
          code?: string | null
          context_valid_after?: string | null
          context_valid_from?: string | null
          context_valid_on?: string | null
          context_valid_to?: string | null
          created_at?: string
          description?: string | null
          id?: never
          is_scoped_tag?: boolean
          label?: string
          level?: number | null
          name: string
          parent_id?: number | null
          path: unknown
          type: Database["public"]["Enums"]["tag_type"]
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string | null
          context_valid_after?: string | null
          context_valid_from?: string | null
          context_valid_on?: string | null
          context_valid_to?: string | null
          created_at?: string
          description?: string | null
          id?: never
          is_scoped_tag?: boolean
          label?: string
          level?: number | null
          name?: string
          parent_id?: number | null
          path?: unknown
          type?: Database["public"]["Enums"]["tag_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tag_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "tag"
            referencedColumns: ["id"]
          },
        ]
      }
      tag_for_unit: {
        Row: {
          created_at: string
          edit_at: string
          edit_by_user_id: number
          edit_comment: string | null
          enterprise_group_id: number | null
          enterprise_id: number | null
          establishment_id: number | null
          id: number
          legal_unit_id: number | null
          tag_id: number
        }
        Insert: {
          created_at?: string
          edit_at?: string
          edit_by_user_id: number
          edit_comment?: string | null
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: never
          legal_unit_id?: number | null
          tag_id: number
        }
        Update: {
          created_at?: string
          edit_at?: string
          edit_by_user_id?: number
          edit_comment?: string | null
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: never
          legal_unit_id?: number | null
          tag_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "tag_for_unit_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tag_for_unit_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "enterprise"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tag_for_unit_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise_def"
            referencedColumns: ["enterprise_id"]
          },
          {
            foreignKeyName: "tag_for_unit_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "tag"
            referencedColumns: ["id"]
          },
        ]
      }
      timeline_enterprise: {
        Row: {
          activity_category_paths: unknown[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          email_address: string | null
          enterprise_id: number | null
          excluded_establishment_ids: number[] | null
          excluded_legal_unit_ids: number[] | null
          fax_number: string | null
          has_legal_unit: boolean | null
          include_unit_in_reports: boolean | null
          included_establishment_ids: number[] | null
          included_legal_unit_ids: number[] | null
          invalid_codes: Json | null
          landline: string | null
          last_edit_at: string | null
          last_edit_by_user_id: number | null
          last_edit_comment: string | null
          legal_form_code: string | null
          legal_form_id: number | null
          legal_form_name: string | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: number | null
          physical_country_id: number | null
          physical_country_iso_2: string | null
          physical_latitude: number | null
          physical_longitude: number | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_id: number | null
          physical_region_path: unknown | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: number | null
          postal_country_id: number | null
          postal_country_iso_2: string | null
          postal_latitude: number | null
          postal_longitude: number | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_id: number | null
          postal_region_path: unknown | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: unknown | null
          primary_establishment_id: number | null
          primary_legal_unit_id: number | null
          related_establishment_ids: number[] | null
          related_legal_unit_ids: number[] | null
          search: unknown | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: unknown | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: unknown | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          unit_id: number
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          valid_after: string
          valid_from: string
          valid_to: string | null
          web_address: string | null
        }
        Insert: {
          activity_category_paths?: unknown[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          email_address?: string | null
          enterprise_id?: number | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          include_unit_in_reports?: boolean | null
          included_establishment_ids?: number[] | null
          included_legal_unit_ids?: number[] | null
          invalid_codes?: Json | null
          landline?: string | null
          last_edit_at?: string | null
          last_edit_by_user_id?: number | null
          last_edit_comment?: string | null
          legal_form_code?: string | null
          legal_form_id?: number | null
          legal_form_name?: string | null
          mobile_number?: string | null
          name?: string | null
          phone_number?: string | null
          physical_address_part1?: string | null
          physical_address_part2?: string | null
          physical_address_part3?: string | null
          physical_altitude?: number | null
          physical_country_id?: number | null
          physical_country_iso_2?: string | null
          physical_latitude?: number | null
          physical_longitude?: number | null
          physical_postcode?: string | null
          physical_postplace?: string | null
          physical_region_code?: string | null
          physical_region_id?: number | null
          physical_region_path?: unknown | null
          postal_address_part1?: string | null
          postal_address_part2?: string | null
          postal_address_part3?: string | null
          postal_altitude?: number | null
          postal_country_id?: number | null
          postal_country_iso_2?: string | null
          postal_latitude?: number | null
          postal_longitude?: number | null
          postal_postcode?: string | null
          postal_postplace?: string | null
          postal_region_code?: string | null
          postal_region_id?: number | null
          postal_region_path?: unknown | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: unknown | null
          primary_establishment_id?: number | null
          primary_legal_unit_id?: number | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: unknown | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: unknown | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: unknown | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          valid_after: string
          valid_from: string
          valid_to?: string | null
          web_address?: string | null
        }
        Update: {
          activity_category_paths?: unknown[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          email_address?: string | null
          enterprise_id?: number | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          include_unit_in_reports?: boolean | null
          included_establishment_ids?: number[] | null
          included_legal_unit_ids?: number[] | null
          invalid_codes?: Json | null
          landline?: string | null
          last_edit_at?: string | null
          last_edit_by_user_id?: number | null
          last_edit_comment?: string | null
          legal_form_code?: string | null
          legal_form_id?: number | null
          legal_form_name?: string | null
          mobile_number?: string | null
          name?: string | null
          phone_number?: string | null
          physical_address_part1?: string | null
          physical_address_part2?: string | null
          physical_address_part3?: string | null
          physical_altitude?: number | null
          physical_country_id?: number | null
          physical_country_iso_2?: string | null
          physical_latitude?: number | null
          physical_longitude?: number | null
          physical_postcode?: string | null
          physical_postplace?: string | null
          physical_region_code?: string | null
          physical_region_id?: number | null
          physical_region_path?: unknown | null
          postal_address_part1?: string | null
          postal_address_part2?: string | null
          postal_address_part3?: string | null
          postal_altitude?: number | null
          postal_country_id?: number | null
          postal_country_iso_2?: string | null
          postal_latitude?: number | null
          postal_longitude?: number | null
          postal_postcode?: string | null
          postal_postplace?: string | null
          postal_region_code?: string | null
          postal_region_id?: number | null
          postal_region_path?: unknown | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: unknown | null
          primary_establishment_id?: number | null
          primary_legal_unit_id?: number | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: unknown | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: unknown | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: unknown | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id?: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          valid_after?: string
          valid_from?: string
          valid_to?: string | null
          web_address?: string | null
        }
        Relationships: []
      }
      timeline_establishment: {
        Row: {
          activity_category_paths: unknown[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          email_address: string | null
          enterprise_id: number | null
          establishment_id: number | null
          fax_number: string | null
          has_legal_unit: boolean | null
          include_unit_in_reports: boolean | null
          invalid_codes: Json | null
          landline: string | null
          last_edit_at: string | null
          last_edit_by_user_id: number | null
          last_edit_comment: string | null
          legal_form_code: string | null
          legal_form_id: number | null
          legal_form_name: string | null
          legal_unit_id: number | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: number | null
          physical_country_id: number | null
          physical_country_iso_2: string | null
          physical_latitude: number | null
          physical_longitude: number | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_id: number | null
          physical_region_path: unknown | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: number | null
          postal_country_id: number | null
          postal_country_iso_2: string | null
          postal_latitude: number | null
          postal_longitude: number | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_id: number | null
          postal_region_path: unknown | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: unknown | null
          primary_for_enterprise: boolean | null
          primary_for_legal_unit: boolean | null
          search: unknown | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: unknown | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: unknown | null
          stats: Json | null
          status_code: string | null
          status_id: number | null
          unit_id: number
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          valid_after: string
          valid_from: string
          valid_to: string | null
          web_address: string | null
        }
        Insert: {
          activity_category_paths?: unknown[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          email_address?: string | null
          enterprise_id?: number | null
          establishment_id?: number | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          include_unit_in_reports?: boolean | null
          invalid_codes?: Json | null
          landline?: string | null
          last_edit_at?: string | null
          last_edit_by_user_id?: number | null
          last_edit_comment?: string | null
          legal_form_code?: string | null
          legal_form_id?: number | null
          legal_form_name?: string | null
          legal_unit_id?: number | null
          mobile_number?: string | null
          name?: string | null
          phone_number?: string | null
          physical_address_part1?: string | null
          physical_address_part2?: string | null
          physical_address_part3?: string | null
          physical_altitude?: number | null
          physical_country_id?: number | null
          physical_country_iso_2?: string | null
          physical_latitude?: number | null
          physical_longitude?: number | null
          physical_postcode?: string | null
          physical_postplace?: string | null
          physical_region_code?: string | null
          physical_region_id?: number | null
          physical_region_path?: unknown | null
          postal_address_part1?: string | null
          postal_address_part2?: string | null
          postal_address_part3?: string | null
          postal_altitude?: number | null
          postal_country_id?: number | null
          postal_country_iso_2?: string | null
          postal_latitude?: number | null
          postal_longitude?: number | null
          postal_postcode?: string | null
          postal_postplace?: string | null
          postal_region_code?: string | null
          postal_region_id?: number | null
          postal_region_path?: unknown | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: unknown | null
          primary_for_enterprise?: boolean | null
          primary_for_legal_unit?: boolean | null
          search?: unknown | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: unknown | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: unknown | null
          stats?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          valid_after: string
          valid_from: string
          valid_to?: string | null
          web_address?: string | null
        }
        Update: {
          activity_category_paths?: unknown[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          email_address?: string | null
          enterprise_id?: number | null
          establishment_id?: number | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          include_unit_in_reports?: boolean | null
          invalid_codes?: Json | null
          landline?: string | null
          last_edit_at?: string | null
          last_edit_by_user_id?: number | null
          last_edit_comment?: string | null
          legal_form_code?: string | null
          legal_form_id?: number | null
          legal_form_name?: string | null
          legal_unit_id?: number | null
          mobile_number?: string | null
          name?: string | null
          phone_number?: string | null
          physical_address_part1?: string | null
          physical_address_part2?: string | null
          physical_address_part3?: string | null
          physical_altitude?: number | null
          physical_country_id?: number | null
          physical_country_iso_2?: string | null
          physical_latitude?: number | null
          physical_longitude?: number | null
          physical_postcode?: string | null
          physical_postplace?: string | null
          physical_region_code?: string | null
          physical_region_id?: number | null
          physical_region_path?: unknown | null
          postal_address_part1?: string | null
          postal_address_part2?: string | null
          postal_address_part3?: string | null
          postal_altitude?: number | null
          postal_country_id?: number | null
          postal_country_iso_2?: string | null
          postal_latitude?: number | null
          postal_longitude?: number | null
          postal_postcode?: string | null
          postal_postplace?: string | null
          postal_region_code?: string | null
          postal_region_id?: number | null
          postal_region_path?: unknown | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: unknown | null
          primary_for_enterprise?: boolean | null
          primary_for_legal_unit?: boolean | null
          search?: unknown | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: unknown | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: unknown | null
          stats?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id?: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          valid_after?: string
          valid_from?: string
          valid_to?: string | null
          web_address?: string | null
        }
        Relationships: []
      }
      timeline_legal_unit: {
        Row: {
          activity_category_paths: unknown[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          email_address: string | null
          enterprise_id: number | null
          excluded_establishment_ids: number[] | null
          fax_number: string | null
          has_legal_unit: boolean | null
          include_unit_in_reports: boolean | null
          included_establishment_ids: number[] | null
          invalid_codes: Json | null
          landline: string | null
          last_edit_at: string | null
          last_edit_by_user_id: number | null
          last_edit_comment: string | null
          legal_form_code: string | null
          legal_form_id: number | null
          legal_form_name: string | null
          legal_unit_id: number | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: number | null
          physical_country_id: number | null
          physical_country_iso_2: string | null
          physical_latitude: number | null
          physical_longitude: number | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_id: number | null
          physical_region_path: unknown | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: number | null
          postal_country_id: number | null
          postal_country_iso_2: string | null
          postal_latitude: number | null
          postal_longitude: number | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_id: number | null
          postal_region_path: unknown | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: unknown | null
          primary_for_enterprise: boolean | null
          related_establishment_ids: number[] | null
          search: unknown | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: unknown | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: unknown | null
          stats: Json | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          unit_id: number
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          valid_after: string
          valid_from: string
          valid_to: string | null
          web_address: string | null
        }
        Insert: {
          activity_category_paths?: unknown[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          email_address?: string | null
          enterprise_id?: number | null
          excluded_establishment_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          include_unit_in_reports?: boolean | null
          included_establishment_ids?: number[] | null
          invalid_codes?: Json | null
          landline?: string | null
          last_edit_at?: string | null
          last_edit_by_user_id?: number | null
          last_edit_comment?: string | null
          legal_form_code?: string | null
          legal_form_id?: number | null
          legal_form_name?: string | null
          legal_unit_id?: number | null
          mobile_number?: string | null
          name?: string | null
          phone_number?: string | null
          physical_address_part1?: string | null
          physical_address_part2?: string | null
          physical_address_part3?: string | null
          physical_altitude?: number | null
          physical_country_id?: number | null
          physical_country_iso_2?: string | null
          physical_latitude?: number | null
          physical_longitude?: number | null
          physical_postcode?: string | null
          physical_postplace?: string | null
          physical_region_code?: string | null
          physical_region_id?: number | null
          physical_region_path?: unknown | null
          postal_address_part1?: string | null
          postal_address_part2?: string | null
          postal_address_part3?: string | null
          postal_altitude?: number | null
          postal_country_id?: number | null
          postal_country_iso_2?: string | null
          postal_latitude?: number | null
          postal_longitude?: number | null
          postal_postcode?: string | null
          postal_postplace?: string | null
          postal_region_code?: string | null
          postal_region_id?: number | null
          postal_region_path?: unknown | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: unknown | null
          primary_for_enterprise?: boolean | null
          related_establishment_ids?: number[] | null
          search?: unknown | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: unknown | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: unknown | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          valid_after: string
          valid_from: string
          valid_to?: string | null
          web_address?: string | null
        }
        Update: {
          activity_category_paths?: unknown[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          email_address?: string | null
          enterprise_id?: number | null
          excluded_establishment_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          include_unit_in_reports?: boolean | null
          included_establishment_ids?: number[] | null
          invalid_codes?: Json | null
          landline?: string | null
          last_edit_at?: string | null
          last_edit_by_user_id?: number | null
          last_edit_comment?: string | null
          legal_form_code?: string | null
          legal_form_id?: number | null
          legal_form_name?: string | null
          legal_unit_id?: number | null
          mobile_number?: string | null
          name?: string | null
          phone_number?: string | null
          physical_address_part1?: string | null
          physical_address_part2?: string | null
          physical_address_part3?: string | null
          physical_altitude?: number | null
          physical_country_id?: number | null
          physical_country_iso_2?: string | null
          physical_latitude?: number | null
          physical_longitude?: number | null
          physical_postcode?: string | null
          physical_postplace?: string | null
          physical_region_code?: string | null
          physical_region_id?: number | null
          physical_region_path?: unknown | null
          postal_address_part1?: string | null
          postal_address_part2?: string | null
          postal_address_part3?: string | null
          postal_altitude?: number | null
          postal_country_id?: number | null
          postal_country_iso_2?: string | null
          postal_latitude?: number | null
          postal_longitude?: number | null
          postal_postcode?: string | null
          postal_postplace?: string | null
          postal_region_code?: string | null
          postal_region_id?: number | null
          postal_region_path?: unknown | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: unknown | null
          primary_for_enterprise?: boolean | null
          related_establishment_ids?: number[] | null
          search?: unknown | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: unknown | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: unknown | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id?: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          valid_after?: string
          valid_from?: string
          valid_to?: string | null
          web_address?: string | null
        }
        Relationships: []
      }
      timesegments: {
        Row: {
          unit_id: number
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          valid_after: string
          valid_to: string
        }
        Insert: {
          unit_id: number
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          valid_after: string
          valid_to: string
        }
        Update: {
          unit_id?: number
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          valid_after?: string
          valid_to?: string
        }
        Relationships: []
      }
      unit_notes: {
        Row: {
          created_at: string
          edit_at: string
          edit_by_user_id: number
          edit_comment: string | null
          enterprise_group_id: number | null
          enterprise_id: number | null
          establishment_id: number | null
          id: number
          legal_unit_id: number | null
          notes: string
        }
        Insert: {
          created_at?: string
          edit_at?: string
          edit_by_user_id: number
          edit_comment?: string | null
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: never
          legal_unit_id?: number | null
          notes: string
        }
        Update: {
          created_at?: string
          edit_at?: string
          edit_by_user_id?: number
          edit_comment?: string | null
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: never
          legal_unit_id?: number | null
          notes?: string
        }
        Relationships: [
          {
            foreignKeyName: "unit_notes_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "unit_notes_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "enterprise"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "unit_notes_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise_def"
            referencedColumns: ["enterprise_id"]
          },
        ]
      }
      unit_size: {
        Row: {
          active: boolean
          code: string
          created_at: string
          custom: boolean
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          created_at?: string
          custom: boolean
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          created_at?: string
          custom?: boolean
          id?: never
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      activity_category_available: {
        Row: {
          code: string | null
          custom: boolean | null
          description: string | null
          id: number | null
          label: string | null
          name: string | null
          parent_path: unknown | null
          path: unknown | null
          standard_code: string | null
        }
        Relationships: []
      }
      activity_category_available_custom: {
        Row: {
          description: string | null
          name: string | null
          path: unknown | null
        }
        Insert: {
          description?: string | null
          name?: string | null
          path?: unknown | null
        }
        Update: {
          description?: string | null
          name?: string | null
          path?: unknown | null
        }
        Relationships: []
      }
      activity_category_isic_v4: {
        Row: {
          code: string | null
          description: string | null
          label: string | null
          name: string | null
          path: unknown | null
          standard: string | null
        }
        Relationships: []
      }
      activity_category_nace_v2_1: {
        Row: {
          code: string | null
          description: string | null
          label: string | null
          name: string | null
          path: unknown | null
          standard: string | null
        }
        Relationships: []
      }
      activity_category_used_def: {
        Row: {
          code: string | null
          description: string | null
          id: number | null
          label: string | null
          name: string | null
          parent_path: unknown | null
          path: unknown | null
          standard_code: string | null
        }
        Relationships: []
      }
      activity_era: {
        Row: {
          category_id: number | null
          data_source_id: number | null
          edit_at: string | null
          edit_by_user_id: number | null
          edit_comment: string | null
          establishment_id: number | null
          id: number | null
          legal_unit_id: number | null
          type: Database["public"]["Enums"]["activity_type"] | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Insert: {
          category_id?: number | null
          data_source_id?: number | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number | null
          legal_unit_id?: number | null
          type?: Database["public"]["Enums"]["activity_type"] | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Update: {
          category_id?: number | null
          data_source_id?: number | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number | null
          legal_unit_id?: number | null
          type?: Database["public"]["Enums"]["activity_type"] | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
        ]
      }
      contact_era: {
        Row: {
          data_source_id: number | null
          edit_at: string | null
          edit_by_user_id: number | null
          edit_comment: string | null
          email_address: string | null
          establishment_id: number | null
          fax_number: string | null
          id: number | null
          landline: string | null
          legal_unit_id: number | null
          mobile_number: string | null
          phone_number: string | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
          web_address: string | null
        }
        Insert: {
          data_source_id?: number | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          email_address?: string | null
          establishment_id?: number | null
          fax_number?: string | null
          id?: number | null
          landline?: string | null
          legal_unit_id?: number | null
          mobile_number?: string | null
          phone_number?: string | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
          web_address?: string | null
        }
        Update: {
          data_source_id?: number | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          email_address?: string | null
          establishment_id?: number | null
          fax_number?: string | null
          id?: number | null
          landline?: string | null
          legal_unit_id?: number | null
          mobile_number?: string | null
          phone_number?: string | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contact_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contact_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contact_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contact_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contact_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
        ]
      }
      country_used_def: {
        Row: {
          id: number | null
          iso_2: string | null
          name: string | null
        }
        Insert: {
          id?: number | null
          iso_2?: string | null
          name?: string | null
        }
        Update: {
          id?: number | null
          iso_2?: string | null
          name?: string | null
        }
        Relationships: []
      }
      country_view: {
        Row: {
          active: boolean | null
          custom: boolean | null
          id: number | null
          iso_2: string | null
          iso_3: string | null
          iso_num: string | null
          name: string | null
        }
        Insert: {
          active?: boolean | null
          custom?: boolean | null
          id?: number | null
          iso_2?: string | null
          iso_3?: string | null
          iso_num?: string | null
          name?: string | null
        }
        Update: {
          active?: boolean | null
          custom?: boolean | null
          id?: number | null
          iso_2?: string | null
          iso_3?: string | null
          iso_num?: string | null
          name?: string | null
        }
        Relationships: []
      }
      data_source_available: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      data_source_custom: {
        Row: {
          code: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      data_source_ordered: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      data_source_system: {
        Row: {
          code: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      data_source_used_def: {
        Row: {
          code: string | null
          id: number | null
          name: string | null
        }
        Insert: {
          code?: string | null
          id?: number | null
          name?: string | null
        }
        Update: {
          code?: string | null
          id?: number | null
          name?: string | null
        }
        Relationships: []
      }
      enterprise_external_idents: {
        Row: {
          external_idents: Json | null
          unit_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_after: string | null
          valid_to: string | null
        }
        Relationships: []
      }
      enterprise_group_role_available: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      enterprise_group_role_custom: {
        Row: {
          code: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      enterprise_group_role_ordered: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      enterprise_group_role_system: {
        Row: {
          code: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      enterprise_group_type_available: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      enterprise_group_type_custom: {
        Row: {
          code: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      enterprise_group_type_ordered: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      enterprise_group_type_system: {
        Row: {
          code: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      establishment_era: {
        Row: {
          active: boolean | null
          birth_date: string | null
          data_source_id: number | null
          death_date: string | null
          edit_at: string | null
          edit_by_user_id: number | null
          edit_comment: string | null
          enterprise_id: number | null
          free_econ_zone: boolean | null
          id: number | null
          invalid_codes: Json | null
          legal_unit_id: number | null
          name: string | null
          primary_for_enterprise: boolean | null
          primary_for_legal_unit: boolean | null
          sector_id: number | null
          short_name: string | null
          status_id: number | null
          unit_size_id: number | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Insert: {
          active?: boolean | null
          birth_date?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          enterprise_id?: number | null
          free_econ_zone?: boolean | null
          id?: number | null
          invalid_codes?: Json | null
          legal_unit_id?: number | null
          name?: string | null
          primary_for_enterprise?: boolean | null
          primary_for_legal_unit?: boolean | null
          sector_id?: number | null
          short_name?: string | null
          status_id?: number | null
          unit_size_id?: number | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Update: {
          active?: boolean | null
          birth_date?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          enterprise_id?: number | null
          free_econ_zone?: boolean | null
          id?: number | null
          invalid_codes?: Json | null
          legal_unit_id?: number | null
          name?: string | null
          primary_for_enterprise?: boolean | null
          primary_for_legal_unit?: boolean | null
          sector_id?: number | null
          short_name?: string | null
          status_id?: number | null
          unit_size_id?: number | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "establishment_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "enterprise"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise_def"
            referencedColumns: ["enterprise_id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "establishment_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "status"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_ordered"
            referencedColumns: ["id"]
          },
        ]
      }
      external_ident_type_active: {
        Row: {
          archived: boolean | null
          by_tag_id: number | null
          code: string | null
          description: string | null
          id: number | null
          name: string | null
          priority: number | null
        }
        Insert: {
          archived?: boolean | null
          by_tag_id?: number | null
          code?: string | null
          description?: string | null
          id?: number | null
          name?: string | null
          priority?: number | null
        }
        Update: {
          archived?: boolean | null
          by_tag_id?: number | null
          code?: string | null
          description?: string | null
          id?: number | null
          name?: string | null
          priority?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "external_ident_type_by_tag_id_fkey"
            columns: ["by_tag_id"]
            isOneToOne: true
            referencedRelation: "tag"
            referencedColumns: ["id"]
          },
        ]
      }
      external_ident_type_ordered: {
        Row: {
          archived: boolean | null
          by_tag_id: number | null
          code: string | null
          description: string | null
          id: number | null
          name: string | null
          priority: number | null
        }
        Insert: {
          archived?: boolean | null
          by_tag_id?: number | null
          code?: string | null
          description?: string | null
          id?: number | null
          name?: string | null
          priority?: number | null
        }
        Update: {
          archived?: boolean | null
          by_tag_id?: number | null
          code?: string | null
          description?: string | null
          id?: number | null
          name?: string | null
          priority?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "external_ident_type_by_tag_id_fkey"
            columns: ["by_tag_id"]
            isOneToOne: true
            referencedRelation: "tag"
            referencedColumns: ["id"]
          },
        ]
      }
      foreign_participation_available: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      foreign_participation_custom: {
        Row: {
          code: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      foreign_participation_ordered: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      foreign_participation_system: {
        Row: {
          code: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      hypopg_hidden_indexes: {
        Row: {
          am_name: unknown | null
          index_name: unknown | null
          indexrelid: unknown | null
          is_hypo: boolean | null
          schema_name: unknown | null
          table_name: unknown | null
        }
        Relationships: []
      }
      hypopg_list_indexes: {
        Row: {
          am_name: unknown | null
          index_name: string | null
          indexrelid: unknown | null
          schema_name: unknown | null
          table_name: unknown | null
        }
        Relationships: []
      }
      import_establishment_current: {
        Row: {
          birth_date: string | null
          data_source_code: string | null
          death_date: string | null
          email_address: string | null
          employees: string | null
          fax_number: string | null
          landline: string | null
          legal_form_code: string | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: string | null
          physical_country_iso_2: string | null
          physical_latitude: string | null
          physical_longitude: string | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: string | null
          postal_country_iso_2: string | null
          postal_latitude: string | null
          postal_longitude: string | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          sector_code: string | null
          stat_ident: string | null
          status_code: string | null
          tag_path: string | null
          tax_ident: string | null
          turnover: string | null
          unit_size_code: string | null
          web_address: string | null
        }
        Relationships: []
      }
      import_establishment_current_for_legal_unit: {
        Row: {
          birth_date: string | null
          data_source_code: string | null
          death_date: string | null
          email_address: string | null
          employees: string | null
          fax_number: string | null
          landline: string | null
          legal_unit_stat_ident: string | null
          legal_unit_tax_ident: string | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: string | null
          physical_country_iso_2: string | null
          physical_latitude: string | null
          physical_longitude: string | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: string | null
          postal_country_iso_2: string | null
          postal_latitude: string | null
          postal_longitude: string | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          stat_ident: string | null
          status_code: string | null
          tag_path: string | null
          tax_ident: string | null
          turnover: string | null
          unit_size_code: string | null
          web_address: string | null
        }
        Relationships: []
      }
      import_establishment_current_without_legal_unit: {
        Row: {
          birth_date: string | null
          data_source_code: string | null
          death_date: string | null
          email_address: string | null
          employees: string | null
          fax_number: string | null
          landline: string | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: string | null
          physical_country_iso_2: string | null
          physical_latitude: string | null
          physical_longitude: string | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: string | null
          postal_country_iso_2: string | null
          postal_latitude: string | null
          postal_longitude: string | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          sector_code: string | null
          stat_ident: string | null
          status_code: string | null
          tag_path: string | null
          tax_ident: string | null
          turnover: string | null
          unit_size_code: string | null
          web_address: string | null
        }
        Relationships: []
      }
      import_establishment_era: {
        Row: {
          birth_date: string | null
          data_source_code: string | null
          death_date: string | null
          email_address: string | null
          employees: string | null
          fax_number: string | null
          landline: string | null
          legal_unit_stat_ident: string | null
          legal_unit_tax_ident: string | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: string | null
          physical_country_iso_2: string | null
          physical_latitude: string | null
          physical_longitude: string | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: string | null
          postal_country_iso_2: string | null
          postal_latitude: string | null
          postal_longitude: string | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          sector_code: string | null
          stat_ident: string | null
          status_code: string | null
          tag_path: string | null
          tax_ident: string | null
          turnover: string | null
          unit_size_code: string | null
          valid_from: string | null
          valid_to: string | null
          web_address: string | null
        }
        Relationships: []
      }
      import_establishment_era_for_legal_unit: {
        Row: {
          birth_date: string | null
          data_source_code: string | null
          death_date: string | null
          email_address: string | null
          employees: string | null
          fax_number: string | null
          landline: string | null
          legal_unit_stat_ident: string | null
          legal_unit_tax_ident: string | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: string | null
          physical_country_iso_2: string | null
          physical_latitude: string | null
          physical_longitude: string | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: string | null
          postal_country_iso_2: string | null
          postal_latitude: string | null
          postal_longitude: string | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          stat_ident: string | null
          status_code: string | null
          tag_path: string | null
          tax_ident: string | null
          turnover: string | null
          unit_size_code: string | null
          valid_from: string | null
          valid_to: string | null
          web_address: string | null
        }
        Relationships: []
      }
      import_establishment_era_without_legal_unit: {
        Row: {
          birth_date: string | null
          data_source_code: string | null
          death_date: string | null
          email_address: string | null
          employees: string | null
          fax_number: string | null
          landline: string | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: string | null
          physical_country_iso_2: string | null
          physical_latitude: string | null
          physical_longitude: string | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: string | null
          postal_country_iso_2: string | null
          postal_latitude: string | null
          postal_longitude: string | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          sector_code: string | null
          stat_ident: string | null
          status_code: string | null
          tag_path: string | null
          tax_ident: string | null
          turnover: string | null
          unit_size_code: string | null
          valid_from: string | null
          valid_to: string | null
          web_address: string | null
        }
        Relationships: []
      }
      import_information: {
        Row: {
          data_table_name: string | null
          definition_id: number | null
          import_definition_slug: string | null
          import_job_slug: string | null
          import_name: string | null
          import_note: string | null
          job_id: number | null
          source_column: string | null
          source_column_priority: number | null
          source_expression:
            | Database["public"]["Enums"]["import_source_expression"]
            | null
          source_value: string | null
          target_column: string | null
          target_schema_name: string | null
          target_type: string | null
          uniquely_identifying: boolean | null
          upload_table_name: string | null
        }
        Relationships: []
      }
      import_legal_unit_current: {
        Row: {
          birth_date: string | null
          data_source_code: string | null
          death_date: string | null
          email_address: string | null
          employees: string | null
          fax_number: string | null
          landline: string | null
          legal_form_code: string | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: string | null
          physical_country_iso_2: string | null
          physical_latitude: string | null
          physical_longitude: string | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: string | null
          postal_country_iso_2: string | null
          postal_latitude: string | null
          postal_longitude: string | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          sector_code: string | null
          stat_ident: string | null
          status_code: string | null
          tag_path: string | null
          tax_ident: string | null
          turnover: string | null
          unit_size_code: string | null
          web_address: string | null
        }
        Relationships: []
      }
      import_legal_unit_era: {
        Row: {
          birth_date: string | null
          data_source_code: string | null
          death_date: string | null
          email_address: string | null
          employees: string | null
          fax_number: string | null
          landline: string | null
          legal_form_code: string | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: string | null
          physical_country_iso_2: string | null
          physical_latitude: string | null
          physical_longitude: string | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: string | null
          postal_country_iso_2: string | null
          postal_latitude: string | null
          postal_longitude: string | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          sector_code: string | null
          stat_ident: string | null
          status_code: string | null
          tag_path: string | null
          tax_ident: string | null
          turnover: string | null
          unit_size_code: string | null
          valid_from: string | null
          valid_to: string | null
          web_address: string | null
        }
        Relationships: []
      }
      legal_form_available: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      legal_form_custom: {
        Row: {
          code: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      legal_form_custom_only: {
        Row: {
          code: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      legal_form_ordered: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      legal_form_system: {
        Row: {
          code: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      legal_form_used_def: {
        Row: {
          code: string | null
          id: number | null
          name: string | null
        }
        Insert: {
          code?: string | null
          id?: number | null
          name?: string | null
        }
        Update: {
          code?: string | null
          id?: number | null
          name?: string | null
        }
        Relationships: []
      }
      legal_unit_era: {
        Row: {
          active: boolean | null
          birth_date: string | null
          data_source_id: number | null
          death_date: string | null
          edit_at: string | null
          edit_by_user_id: number | null
          edit_comment: string | null
          enterprise_id: number | null
          foreign_participation_id: number | null
          free_econ_zone: boolean | null
          id: number | null
          invalid_codes: Json | null
          legal_form_id: number | null
          name: string | null
          primary_for_enterprise: boolean | null
          sector_id: number | null
          short_name: string | null
          status_id: number | null
          unit_size_id: number | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Insert: {
          active?: boolean | null
          birth_date?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          enterprise_id?: number | null
          foreign_participation_id?: number | null
          free_econ_zone?: boolean | null
          id?: number | null
          invalid_codes?: Json | null
          legal_form_id?: number | null
          name?: string | null
          primary_for_enterprise?: boolean | null
          sector_id?: number | null
          short_name?: string | null
          status_id?: number | null
          unit_size_id?: number | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Update: {
          active?: boolean | null
          birth_date?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          enterprise_id?: number | null
          foreign_participation_id?: number | null
          free_econ_zone?: boolean | null
          id?: number | null
          invalid_codes?: Json | null
          legal_form_id?: number | null
          name?: string | null
          primary_for_enterprise?: boolean | null
          sector_id?: number | null
          short_name?: string | null
          status_id?: number | null
          unit_size_id?: number | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "legal_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "enterprise"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise_def"
            referencedColumns: ["enterprise_id"]
          },
          {
            foreignKeyName: "legal_unit_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["legal_form_id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "legal_unit_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "status"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_ordered"
            referencedColumns: ["id"]
          },
        ]
      }
      location_era: {
        Row: {
          address_part1: string | null
          address_part2: string | null
          address_part3: string | null
          altitude: number | null
          country_id: number | null
          data_source_id: number | null
          edit_at: string | null
          edit_by_user_id: number | null
          edit_comment: string | null
          establishment_id: number | null
          id: number | null
          latitude: number | null
          legal_unit_id: number | null
          longitude: number | null
          postcode: string | null
          postplace: string | null
          region_id: number | null
          type: Database["public"]["Enums"]["location_type"] | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Insert: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          altitude?: number | null
          country_id?: number | null
          data_source_id?: number | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number | null
          latitude?: number | null
          legal_unit_id?: number | null
          longitude?: number | null
          postcode?: string | null
          postplace?: string | null
          region_id?: number | null
          type?: Database["public"]["Enums"]["location_type"] | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Update: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          altitude?: number | null
          country_id?: number | null
          data_source_id?: number | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number | null
          latitude?: number | null
          legal_unit_id?: number | null
          longitude?: number | null
          postcode?: string | null
          postplace?: string | null
          region_id?: number | null
          type?: Database["public"]["Enums"]["location_type"] | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country_view"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user_with_role"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "region"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "region_used_def"
            referencedColumns: ["id"]
          },
        ]
      }
      person_role_available: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      person_role_custom: {
        Row: {
          code: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      person_role_ordered: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      person_role_system: {
        Row: {
          code: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      pg_stat_monitor: {
        Row: {
          application_name: string | null
          bucket: number | null
          bucket_done: boolean | null
          bucket_start_time: string | null
          calls: number | null
          client_ip: unknown | null
          cmd_type: number | null
          cmd_type_text: string | null
          comments: string | null
          cpu_sys_time: number | null
          cpu_user_time: number | null
          datname: string | null
          dbid: unknown | null
          elevel: number | null
          jit_deform_count: number | null
          jit_deform_time: number | null
          jit_emission_count: number | null
          jit_emission_time: number | null
          jit_functions: number | null
          jit_generation_time: number | null
          jit_inlining_count: number | null
          jit_inlining_time: number | null
          jit_optimization_count: number | null
          jit_optimization_time: number | null
          local_blk_read_time: number | null
          local_blk_write_time: number | null
          local_blks_dirtied: number | null
          local_blks_hit: number | null
          local_blks_read: number | null
          local_blks_written: number | null
          max_exec_time: number | null
          max_plan_time: number | null
          mean_exec_time: number | null
          mean_plan_time: number | null
          message: string | null
          min_exec_time: number | null
          min_plan_time: number | null
          minmax_stats_since: string | null
          pgsm_query_id: number | null
          planid: number | null
          plans: number | null
          query: string | null
          query_plan: string | null
          queryid: number | null
          relations: string[] | null
          resp_calls: string[] | null
          rows: number | null
          shared_blk_read_time: number | null
          shared_blk_write_time: number | null
          shared_blks_dirtied: number | null
          shared_blks_hit: number | null
          shared_blks_read: number | null
          shared_blks_written: number | null
          sqlcode: string | null
          stats_since: string | null
          stddev_exec_time: number | null
          stddev_plan_time: number | null
          temp_blk_read_time: number | null
          temp_blk_write_time: number | null
          temp_blks_read: number | null
          temp_blks_written: number | null
          top_query: string | null
          top_queryid: number | null
          toplevel: boolean | null
          total_exec_time: number | null
          total_plan_time: number | null
          userid: unknown | null
          username: string | null
          wal_bytes: number | null
          wal_fpi: number | null
          wal_records: number | null
        }
        Relationships: []
      }
      pg_stat_statements: {
        Row: {
          calls: number | null
          dbid: unknown | null
          jit_deform_count: number | null
          jit_deform_time: number | null
          jit_emission_count: number | null
          jit_emission_time: number | null
          jit_functions: number | null
          jit_generation_time: number | null
          jit_inlining_count: number | null
          jit_inlining_time: number | null
          jit_optimization_count: number | null
          jit_optimization_time: number | null
          local_blk_read_time: number | null
          local_blk_write_time: number | null
          local_blks_dirtied: number | null
          local_blks_hit: number | null
          local_blks_read: number | null
          local_blks_written: number | null
          max_exec_time: number | null
          max_plan_time: number | null
          mean_exec_time: number | null
          mean_plan_time: number | null
          min_exec_time: number | null
          min_plan_time: number | null
          minmax_stats_since: string | null
          plans: number | null
          query: string | null
          queryid: number | null
          rows: number | null
          shared_blk_read_time: number | null
          shared_blk_write_time: number | null
          shared_blks_dirtied: number | null
          shared_blks_hit: number | null
          shared_blks_read: number | null
          shared_blks_written: number | null
          stats_since: string | null
          stddev_exec_time: number | null
          stddev_plan_time: number | null
          temp_blk_read_time: number | null
          temp_blk_write_time: number | null
          temp_blks_read: number | null
          temp_blks_written: number | null
          toplevel: boolean | null
          total_exec_time: number | null
          total_plan_time: number | null
          userid: unknown | null
          wal_bytes: number | null
          wal_fpi: number | null
          wal_records: number | null
        }
        Relationships: []
      }
      pg_stat_statements_info: {
        Row: {
          dealloc: number | null
          stats_reset: string | null
        }
        Relationships: []
      }
      region_upload: {
        Row: {
          center_altitude: string | null
          center_latitude: string | null
          center_longitude: string | null
          name: string | null
          path: string | null
        }
        Insert: {
          center_altitude?: never
          center_latitude?: never
          center_longitude?: never
          name?: string | null
          path?: never
        }
        Update: {
          center_altitude?: never
          center_latitude?: never
          center_longitude?: never
          name?: string | null
          path?: never
        }
        Relationships: []
      }
      region_used_def: {
        Row: {
          code: string | null
          id: number | null
          label: string | null
          level: number | null
          name: string | null
          path: unknown | null
        }
        Insert: {
          code?: string | null
          id?: number | null
          label?: string | null
          level?: number | null
          name?: string | null
          path?: unknown | null
        }
        Update: {
          code?: string | null
          id?: number | null
          label?: string | null
          level?: number | null
          name?: string | null
          path?: unknown | null
        }
        Relationships: []
      }
      relative_period_with_time: {
        Row: {
          active: boolean | null
          code: Database["public"]["Enums"]["relative_period_code"] | null
          id: number | null
          name_when_input: string | null
          name_when_query: string | null
          scope: Database["public"]["Enums"]["relative_period_scope"] | null
          valid_from: string | null
          valid_on: string | null
          valid_to: string | null
        }
        Insert: {
          active?: boolean | null
          code?: Database["public"]["Enums"]["relative_period_code"] | null
          id?: number | null
          name_when_input?: string | null
          name_when_query?: string | null
          scope?: Database["public"]["Enums"]["relative_period_scope"] | null
          valid_from?: never
          valid_on?: never
          valid_to?: never
        }
        Update: {
          active?: boolean | null
          code?: Database["public"]["Enums"]["relative_period_code"] | null
          id?: number | null
          name_when_input?: string | null
          name_when_query?: string | null
          scope?: Database["public"]["Enums"]["relative_period_scope"] | null
          valid_from?: never
          valid_on?: never
          valid_to?: never
        }
        Relationships: []
      }
      reorg_type_available: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          description: string | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      reorg_type_custom: {
        Row: {
          code: string | null
          description: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          description?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          description?: string | null
          name?: string | null
        }
        Relationships: []
      }
      reorg_type_ordered: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          description: string | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      reorg_type_system: {
        Row: {
          code: string | null
          description: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          description?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          description?: string | null
          name?: string | null
        }
        Relationships: []
      }
      sector_available: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          description: string | null
          id: number | null
          label: string | null
          name: string | null
          parent_id: number | null
          path: unknown | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_id?: number | null
          path?: unknown | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_id?: number | null
          path?: unknown | null
          updated_at?: string | null
        }
        Relationships: []
      }
      sector_custom: {
        Row: {
          description: string | null
          name: string | null
          path: unknown | null
        }
        Insert: {
          description?: string | null
          name?: string | null
          path?: unknown | null
        }
        Update: {
          description?: string | null
          name?: string | null
          path?: unknown | null
        }
        Relationships: []
      }
      sector_custom_only: {
        Row: {
          description: string | null
          name: string | null
          path: unknown | null
        }
        Insert: {
          description?: string | null
          name?: string | null
          path?: unknown | null
        }
        Update: {
          description?: string | null
          name?: string | null
          path?: unknown | null
        }
        Relationships: []
      }
      sector_ordered: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          description: string | null
          id: number | null
          label: string | null
          name: string | null
          parent_id: number | null
          path: unknown | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_id?: number | null
          path?: unknown | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_id?: number | null
          path?: unknown | null
          updated_at?: string | null
        }
        Relationships: []
      }
      sector_system: {
        Row: {
          description: string | null
          name: string | null
          path: unknown | null
        }
        Insert: {
          description?: string | null
          name?: string | null
          path?: unknown | null
        }
        Update: {
          description?: string | null
          name?: string | null
          path?: unknown | null
        }
        Relationships: []
      }
      sector_used_def: {
        Row: {
          code: string | null
          id: number | null
          label: string | null
          name: string | null
          path: unknown | null
        }
        Insert: {
          code?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          path?: unknown | null
        }
        Update: {
          code?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          path?: unknown | null
        }
        Relationships: []
      }
      stat_definition_active: {
        Row: {
          archived: boolean | null
          code: string | null
          description: string | null
          frequency: Database["public"]["Enums"]["stat_frequency"] | null
          id: number | null
          name: string | null
          priority: number | null
          type: Database["public"]["Enums"]["stat_type"] | null
        }
        Insert: {
          archived?: boolean | null
          code?: string | null
          description?: string | null
          frequency?: Database["public"]["Enums"]["stat_frequency"] | null
          id?: number | null
          name?: string | null
          priority?: number | null
          type?: Database["public"]["Enums"]["stat_type"] | null
        }
        Update: {
          archived?: boolean | null
          code?: string | null
          description?: string | null
          frequency?: Database["public"]["Enums"]["stat_frequency"] | null
          id?: number | null
          name?: string | null
          priority?: number | null
          type?: Database["public"]["Enums"]["stat_type"] | null
        }
        Relationships: []
      }
      stat_definition_ordered: {
        Row: {
          archived: boolean | null
          code: string | null
          description: string | null
          frequency: Database["public"]["Enums"]["stat_frequency"] | null
          id: number | null
          name: string | null
          priority: number | null
          type: Database["public"]["Enums"]["stat_type"] | null
        }
        Insert: {
          archived?: boolean | null
          code?: string | null
          description?: string | null
          frequency?: Database["public"]["Enums"]["stat_frequency"] | null
          id?: number | null
          name?: string | null
          priority?: number | null
          type?: Database["public"]["Enums"]["stat_type"] | null
        }
        Update: {
          archived?: boolean | null
          code?: string | null
          description?: string | null
          frequency?: Database["public"]["Enums"]["stat_frequency"] | null
          id?: number | null
          name?: string | null
          priority?: number | null
          type?: Database["public"]["Enums"]["stat_type"] | null
        }
        Relationships: []
      }
      stat_for_unit_era: {
        Row: {
          data_source_id: number | null
          establishment_id: number | null
          id: number | null
          legal_unit_id: number | null
          stat_definition_id: number | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
          value_bool: boolean | null
          value_float: number | null
          value_int: number | null
          value_string: string | null
        }
        Insert: {
          data_source_id?: number | null
          establishment_id?: number | null
          id?: number | null
          legal_unit_id?: number | null
          stat_definition_id?: number | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
          value_bool?: boolean | null
          value_float?: number | null
          value_int?: number | null
          value_string?: string | null
        }
        Update: {
          data_source_id?: number | null
          establishment_id?: number | null
          id?: number | null
          legal_unit_id?: number | null
          stat_definition_id?: number | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
          value_bool?: boolean | null
          value_float?: number | null
          value_int?: number | null
          value_string?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "stat_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_stat_definition_id_fkey"
            columns: ["stat_definition_id"]
            isOneToOne: false
            referencedRelation: "stat_definition"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_stat_definition_id_fkey"
            columns: ["stat_definition_id"]
            isOneToOne: false
            referencedRelation: "stat_definition_active"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_stat_definition_id_fkey"
            columns: ["stat_definition_id"]
            isOneToOne: false
            referencedRelation: "stat_definition_ordered"
            referencedColumns: ["id"]
          },
        ]
      }
      statistical_history_def: {
        Row: {
          births: number | null
          count: number | null
          deaths: number | null
          legal_form_change_count: number | null
          month: number | null
          name_change_count: number | null
          physical_address_change_count: number | null
          physical_country_change_count: number | null
          physical_region_change_count: number | null
          primary_activity_category_change_count: number | null
          resolution: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count: number | null
          sector_change_count: number | null
          stats_summary: Json | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          year: number | null
        }
        Relationships: []
      }
      statistical_history_facet_def: {
        Row: {
          births: number | null
          count: number | null
          deaths: number | null
          legal_form_change_count: number | null
          legal_form_id: number | null
          month: number | null
          name_change_count: number | null
          physical_address_change_count: number | null
          physical_country_change_count: number | null
          physical_country_id: number | null
          physical_region_change_count: number | null
          physical_region_path: unknown | null
          primary_activity_category_change_count: number | null
          primary_activity_category_path: unknown | null
          resolution: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count: number | null
          secondary_activity_category_path: unknown | null
          sector_change_count: number | null
          sector_path: unknown | null
          stats_summary: Json | null
          status_change_count: number | null
          status_id: number | null
          unit_size_change_count: number | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          year: number | null
        }
        Relationships: []
      }
      statistical_unit_def: {
        Row: {
          activity_category_paths: unknown[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          email_address: string | null
          excluded_enterprise_ids: number[] | null
          excluded_establishment_ids: number[] | null
          excluded_legal_unit_ids: number[] | null
          external_idents: Json | null
          fax_number: string | null
          has_legal_unit: boolean | null
          include_unit_in_reports: boolean | null
          included_enterprise_count: number | null
          included_enterprise_ids: number[] | null
          included_establishment_count: number | null
          included_establishment_ids: number[] | null
          included_legal_unit_count: number | null
          included_legal_unit_ids: number[] | null
          invalid_codes: Json | null
          landline: string | null
          last_edit_at: string | null
          last_edit_by_user_id: number | null
          last_edit_comment: string | null
          legal_form_code: string | null
          legal_form_id: number | null
          legal_form_name: string | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: number | null
          physical_country_id: number | null
          physical_country_iso_2: string | null
          physical_latitude: number | null
          physical_longitude: number | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_id: number | null
          physical_region_path: unknown | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: number | null
          postal_country_id: number | null
          postal_country_iso_2: string | null
          postal_latitude: number | null
          postal_longitude: number | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_id: number | null
          postal_region_path: unknown | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: unknown | null
          related_enterprise_ids: number[] | null
          related_establishment_ids: number[] | null
          related_legal_unit_ids: number[] | null
          search: unknown | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: unknown | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: unknown | null
          stats: Json | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          tag_paths: unknown[] | null
          unit_id: number | null
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
          web_address: string | null
        }
        Relationships: []
      }
      statistical_unit_facet_def: {
        Row: {
          count: number | null
          legal_form_id: number | null
          physical_country_id: number | null
          physical_region_path: unknown | null
          primary_activity_category_path: unknown | null
          sector_path: unknown | null
          stats_summary: Json | null
          status_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from: string | null
          valid_to: string | null
        }
        Relationships: []
      }
      time_context: {
        Row: {
          code: Database["public"]["Enums"]["relative_period_code"] | null
          ident: string | null
          name_when_input: string | null
          name_when_query: string | null
          path: unknown | null
          scope: Database["public"]["Enums"]["relative_period_scope"] | null
          type: Database["public"]["Enums"]["time_context_type"] | null
          valid_from: string | null
          valid_on: string | null
          valid_to: string | null
        }
        Relationships: []
      }
      timeline_enterprise_def: {
        Row: {
          activity_category_paths: unknown[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          email_address: string | null
          enterprise_id: number | null
          excluded_establishment_ids: number[] | null
          excluded_legal_unit_ids: number[] | null
          fax_number: string | null
          has_legal_unit: boolean | null
          include_unit_in_reports: boolean | null
          included_establishment_ids: number[] | null
          included_legal_unit_ids: number[] | null
          invalid_codes: Json | null
          landline: string | null
          last_edit_at: string | null
          last_edit_by_user_id: number | null
          last_edit_comment: string | null
          legal_form_code: string | null
          legal_form_id: number | null
          legal_form_name: string | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: number | null
          physical_country_id: number | null
          physical_country_iso_2: string | null
          physical_latitude: number | null
          physical_longitude: number | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_id: number | null
          physical_region_path: unknown | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: number | null
          postal_country_id: number | null
          postal_country_iso_2: string | null
          postal_latitude: number | null
          postal_longitude: number | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_id: number | null
          postal_region_path: unknown | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: unknown | null
          primary_establishment_id: number | null
          primary_legal_unit_id: number | null
          related_establishment_ids: number[] | null
          related_legal_unit_ids: number[] | null
          search: unknown | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: unknown | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: unknown | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          unit_id: number | null
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
          web_address: string | null
        }
        Relationships: []
      }
      timeline_establishment_def: {
        Row: {
          activity_category_paths: unknown[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          email_address: string | null
          enterprise_id: number | null
          establishment_id: number | null
          fax_number: string | null
          has_legal_unit: boolean | null
          include_unit_in_reports: boolean | null
          invalid_codes: Json | null
          landline: string | null
          last_edit_at: string | null
          last_edit_by_user_id: number | null
          last_edit_comment: string | null
          legal_form_code: string | null
          legal_form_id: number | null
          legal_form_name: string | null
          legal_unit_id: number | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: number | null
          physical_country_id: number | null
          physical_country_iso_2: string | null
          physical_latitude: number | null
          physical_longitude: number | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_id: number | null
          physical_region_path: unknown | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: number | null
          postal_country_id: number | null
          postal_country_iso_2: string | null
          postal_latitude: number | null
          postal_longitude: number | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_id: number | null
          postal_region_path: unknown | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: unknown | null
          primary_for_enterprise: boolean | null
          primary_for_legal_unit: boolean | null
          search: unknown | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: unknown | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: unknown | null
          stats: Json | null
          status_code: string | null
          status_id: number | null
          unit_id: number | null
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
          web_address: string | null
        }
        Relationships: [
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["secondary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["primary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["secondary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["primary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["secondary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["primary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "enterprise"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise_def"
            referencedColumns: ["enterprise_id"]
          },
          {
            foreignKeyName: "establishment_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "status"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["postal_country_id"]
            isOneToOne: false
            referencedRelation: "country"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["physical_country_id"]
            isOneToOne: false
            referencedRelation: "country"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["postal_country_id"]
            isOneToOne: false
            referencedRelation: "country_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["physical_country_id"]
            isOneToOne: false
            referencedRelation: "country_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["postal_country_id"]
            isOneToOne: false
            referencedRelation: "country_view"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["physical_country_id"]
            isOneToOne: false
            referencedRelation: "country_view"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["physical_region_id"]
            isOneToOne: false
            referencedRelation: "region"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["postal_region_id"]
            isOneToOne: false
            referencedRelation: "region"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["physical_region_id"]
            isOneToOne: false
            referencedRelation: "region_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["postal_region_id"]
            isOneToOne: false
            referencedRelation: "region_used_def"
            referencedColumns: ["id"]
          },
        ]
      }
      timeline_legal_unit_def: {
        Row: {
          activity_category_paths: unknown[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          email_address: string | null
          enterprise_id: number | null
          excluded_establishment_ids: number[] | null
          fax_number: string | null
          has_legal_unit: boolean | null
          include_unit_in_reports: boolean | null
          included_establishment_ids: number[] | null
          invalid_codes: Json | null
          landline: string | null
          last_edit_at: string | null
          last_edit_by_user_id: number | null
          last_edit_comment: string | null
          legal_form_code: string | null
          legal_form_id: number | null
          legal_form_name: string | null
          legal_unit_id: number | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: number | null
          physical_country_id: number | null
          physical_country_iso_2: string | null
          physical_latitude: number | null
          physical_longitude: number | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_id: number | null
          physical_region_path: unknown | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: number | null
          postal_country_id: number | null
          postal_country_iso_2: string | null
          postal_latitude: number | null
          postal_longitude: number | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_id: number | null
          postal_region_path: unknown | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: unknown | null
          primary_for_enterprise: boolean | null
          related_establishment_ids: number[] | null
          search: unknown | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: unknown | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: unknown | null
          stats: Json | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          unit_id: number | null
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
          web_address: string | null
        }
        Relationships: [
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["secondary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["primary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["secondary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["primary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["secondary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["primary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "enterprise"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise_def"
            referencedColumns: ["enterprise_id"]
          },
          {
            foreignKeyName: "legal_unit_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "status"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_ordered"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["physical_country_id"]
            isOneToOne: false
            referencedRelation: "country"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["postal_country_id"]
            isOneToOne: false
            referencedRelation: "country"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["physical_country_id"]
            isOneToOne: false
            referencedRelation: "country_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["postal_country_id"]
            isOneToOne: false
            referencedRelation: "country_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["physical_country_id"]
            isOneToOne: false
            referencedRelation: "country_view"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["postal_country_id"]
            isOneToOne: false
            referencedRelation: "country_view"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["postal_region_id"]
            isOneToOne: false
            referencedRelation: "region"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["physical_region_id"]
            isOneToOne: false
            referencedRelation: "region"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["postal_region_id"]
            isOneToOne: false
            referencedRelation: "region_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["physical_region_id"]
            isOneToOne: false
            referencedRelation: "region_used_def"
            referencedColumns: ["id"]
          },
        ]
      }
      timepoints: {
        Row: {
          timepoint: string | null
          unit_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
        }
        Relationships: []
      }
      timesegments_def: {
        Row: {
          unit_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_after: string | null
          valid_to: string | null
        }
        Relationships: []
      }
      unit_size_available: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      unit_size_custom: {
        Row: {
          code: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      unit_size_ordered: {
        Row: {
          active: boolean | null
          code: string | null
          created_at: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      unit_size_system: {
        Row: {
          code: string | null
          name: string | null
        }
        Insert: {
          code?: string | null
          name?: string | null
        }
        Update: {
          code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      user_with_role: {
        Row: {
          email: string | null
          id: number | null
          statbus_role: Database["public"]["Enums"]["statbus_role"] | null
        }
        Insert: {
          email?: string | null
          id?: number | null
          statbus_role?: Database["public"]["Enums"]["statbus_role"] | null
        }
        Update: {
          email?: string | null
          id?: number | null
          statbus_role?: Database["public"]["Enums"]["statbus_role"] | null
        }
        Relationships: []
      }
    }
    Functions: {
      __plpgsql_show_dependency_tb: {
        Args:
          | {
              funcoid: unknown
              relid?: unknown
              anyelememttype?: unknown
              anyenumtype?: unknown
              anyrangetype?: unknown
              anycompatibletype?: unknown
              anycompatiblerangetype?: unknown
            }
          | {
              name: string
              relid?: unknown
              anyelememttype?: unknown
              anyenumtype?: unknown
              anyrangetype?: unknown
              anycompatibletype?: unknown
              anycompatiblerangetype?: unknown
            }
        Returns: {
          type: string
          oid: unknown
          schema: string
          name: string
          params: string
        }[]
      }
      _ltree_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      _ltree_gist_options: {
        Args: { "": unknown }
        Returns: undefined
      }
      activity_category_hierarchy: {
        Args: { activity_category_id: number }
        Returns: Json
      }
      activity_category_standard_hierarchy: {
        Args: { standard_id: number }
        Returns: Json
      }
      activity_category_used_derive: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      activity_hierarchy: {
        Args: {
          parent_establishment_id?: number
          parent_legal_unit_id?: number
          valid_on?: string
        }
        Returns: Json
      }
      after_to_overlaps: {
        Args: { after1: unknown; to1: unknown; after2: unknown; to2: unknown }
        Returns: boolean
      }
      algorithm_sign: {
        Args: { signables: string; secret: string; algorithm: string }
        Returns: string
      }
      armor: {
        Args: { "": string }
        Returns: string
      }
      array_distinct_concat_final: {
        Args: { "": unknown }
        Returns: unknown
      }
      bytea_to_text: {
        Args: { data: string }
        Returns: string
      }
      connect_legal_unit_to_enterprise: {
        Args: {
          legal_unit_id: number
          enterprise_id: number
          valid_from?: string
          valid_to?: string
        }
        Returns: Json
      }
      contact_hierarchy: {
        Args: { parent_establishment_id: number; parent_legal_unit_id: number }
        Returns: Json
      }
      country_hierarchy: {
        Args: { country_id: number }
        Returns: Json
      }
      country_used_derive: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      create_temporal_foreign_key: {
        Args: {
          constraint_name: string
          from_table: string
          from_column: string
          from_range_column: string
          to_table: string
          to_column: string
          to_range_column: string
        }
        Returns: undefined
      }
      data_source_hierarchy: {
        Args: { data_source_id: number }
        Returns: Json
      }
      data_source_used_derive: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      dearmor: {
        Args: { "": string }
        Returns: string
      }
      decode_error_level: {
        Args: { elevel: number }
        Returns: string
      }
      drop_temporal_foreign_key: {
        Args: { constraint_name: string; from_table: string; to_table: string }
        Returns: undefined
      }
      enterprise_hierarchy: {
        Args: {
          enterprise_id: number
          scope?: Database["public"]["Enums"]["hierarchy_scope"]
          valid_on?: string
        }
        Returns: Json
      }
      establishment_hierarchy: {
        Args: {
          establishment_id: number
          parent_legal_unit_id: number
          parent_enterprise_id: number
          scope?: Database["public"]["Enums"]["hierarchy_scope"]
          valid_on?: string
        }
        Returns: Json
      }
      external_idents_hierarchy: {
        Args: {
          parent_establishment_id?: number
          parent_legal_unit_id?: number
          parent_enterprise_id?: number
          parent_enterprise_group_id?: number
        }
        Returns: Json
      }
      from_to_overlaps: {
        Args: { start1: unknown; end1: unknown; start2: unknown; end2: unknown }
        Returns: boolean
      }
      gbt_bit_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_bool_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_bool_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_bpchar_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_bytea_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_cash_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_cash_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_date_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_date_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_decompress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_enum_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_enum_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_float4_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_float4_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_float8_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_float8_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_inet_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_int2_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_int2_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_int4_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_int4_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_int8_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_int8_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_intv_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_intv_decompress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_intv_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_macad_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_macad_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_macad8_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_macad8_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_numeric_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_oid_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_oid_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_text_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_time_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_time_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_timetz_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_ts_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_ts_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_tstz_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_uuid_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_uuid_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_var_decompress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbt_var_fetch: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbtreekey_var_in: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbtreekey_var_out: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbtreekey16_in: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbtreekey16_out: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbtreekey2_in: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbtreekey2_out: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbtreekey32_in: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbtreekey32_out: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbtreekey4_in: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbtreekey4_out: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbtreekey8_in: {
        Args: { "": unknown }
        Returns: unknown
      }
      gbtreekey8_out: {
        Args: { "": unknown }
        Returns: unknown
      }
      gen_random_bytes: {
        Args: { "": number }
        Returns: string
      }
      gen_random_uuid: {
        Args: Record<PropertyKey, never>
        Returns: string
      }
      gen_salt: {
        Args: { "": string }
        Returns: string
      }
      generate_mermaid_er_diagram: {
        Args: Record<PropertyKey, never>
        Returns: string
      }
      get_cmd_type: {
        Args: { cmd_type: number }
        Returns: string
      }
      get_external_idents: {
        Args: {
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          unit_id: number
        }
        Returns: Json
      }
      get_histogram_timings: {
        Args: Record<PropertyKey, never>
        Returns: string
      }
      get_import_job_progress: {
        Args: { job_id: number }
        Returns: Json
      }
      get_jsonb_stats: {
        Args: {
          p_establishment_id: number
          p_legal_unit_id: number
          p_valid_after: string
          p_valid_to: string
        }
        Returns: Json
      }
      get_statistical_history_periods: {
        Args: {
          p_resolution?: Database["public"]["Enums"]["history_resolution"]
          p_valid_after?: string
          p_valid_to?: string
        }
        Returns: {
          resolution: Database["public"]["Enums"]["history_resolution"]
          year: number
          month: number
          prev_stop: string
          curr_start: string
          curr_stop: string
        }[]
      }
      grant_role: {
        Args: {
          user_sub: string
          new_role: Database["public"]["Enums"]["statbus_role"]
        }
        Returns: boolean
      }
      gtrgm_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gtrgm_decompress: {
        Args: { "": unknown }
        Returns: unknown
      }
      gtrgm_in: {
        Args: { "": unknown }
        Returns: unknown
      }
      gtrgm_options: {
        Args: { "": unknown }
        Returns: undefined
      }
      gtrgm_out: {
        Args: { "": unknown }
        Returns: unknown
      }
      hash_encode: {
        Args: { "": number }
        Returns: string
      }
      hash_ltree: {
        Args: { "": unknown }
        Returns: number
      }
      histogram: {
        Args: { _bucket: number; _quryid: number }
        Returns: Record<string, unknown>[]
      }
      http: {
        Args: { request: Database["public"]["CompositeTypes"]["http_request"] }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      }
      http_delete: {
        Args:
          | { uri: string }
          | { uri: string; content: string; content_type: string }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      }
      http_get: {
        Args: { uri: string } | { uri: string; data: Json }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      }
      http_head: {
        Args: { uri: string }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      }
      http_header: {
        Args: { field: string; value: string }
        Returns: Database["public"]["CompositeTypes"]["http_header"]
      }
      http_headers: {
        Args: Record<PropertyKey, never>
        Returns: Database["public"]["CompositeTypes"]["http_header"][]
      }
      http_list_curlopt: {
        Args: Record<PropertyKey, never>
        Returns: {
          curlopt: string
          value: string
        }[]
      }
      http_patch: {
        Args: { uri: string; content: string; content_type: string }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      }
      http_post: {
        Args:
          | { uri: string; content: string; content_type: string }
          | { uri: string; data: Json }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      }
      http_put: {
        Args: { uri: string; content: string; content_type: string }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      }
      http_reset_curlopt: {
        Args: Record<PropertyKey, never>
        Returns: boolean
      }
      http_set_curlopt: {
        Args: { curlopt: string; value: string }
        Returns: boolean
      }
      hypopg: {
        Args: Record<PropertyKey, never>
        Returns: Record<string, unknown>[]
      }
      hypopg_create_index: {
        Args: { sql_order: string }
        Returns: Record<string, unknown>[]
      }
      hypopg_drop_index: {
        Args: { indexid: unknown }
        Returns: boolean
      }
      hypopg_get_indexdef: {
        Args: { indexid: unknown }
        Returns: string
      }
      hypopg_hidden_indexes: {
        Args: Record<PropertyKey, never>
        Returns: {
          indexid: unknown
        }[]
      }
      hypopg_hide_index: {
        Args: { indexid: unknown }
        Returns: boolean
      }
      hypopg_relation_size: {
        Args: { indexid: unknown }
        Returns: number
      }
      hypopg_reset: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      hypopg_reset_index: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      hypopg_unhide_all_indexes: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      hypopg_unhide_index: {
        Args: { indexid: unknown }
        Returns: boolean
      }
      id_decode: {
        Args: { "": string }
        Returns: number[]
      }
      id_decode_once: {
        Args: { "": string }
        Returns: number
      }
      id_encode: {
        Args: { "": number } | { "": number[] }
        Returns: string
      }
      index_advisor: {
        Args: { query: string }
        Returns: {
          startup_cost_before: Json
          startup_cost_after: Json
          total_cost_before: Json
          total_cost_after: Json
          index_statements: string[]
          errors: string[]
        }[]
      }
      jsonb_stats_summary_merge: {
        Args: { a: Json; b: Json }
        Returns: Json
      }
      jsonb_stats_to_summary: {
        Args: { state: Json; stats: Json }
        Returns: Json
      }
      jsonb_stats_to_summary_round: {
        Args: { state: Json }
        Returns: Json
      }
      lca: {
        Args: { "": unknown[] }
        Returns: unknown
      }
      legal_form_hierarchy: {
        Args: { legal_form_id: number }
        Returns: Json
      }
      legal_form_used_derive: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      legal_unit_hierarchy: {
        Args: {
          legal_unit_id: number
          parent_enterprise_id: number
          scope?: Database["public"]["Enums"]["hierarchy_scope"]
          valid_on?: string
        }
        Returns: Json
      }
      list_active_sessions: {
        Args: Record<PropertyKey, never>
        Returns: Json[]
      }
      location_hierarchy: {
        Args: {
          parent_establishment_id?: number
          parent_legal_unit_id?: number
          valid_on?: string
        }
        Returns: Json
      }
      login: {
        Args: { email: string; password: string }
        Returns: Json
      }
      logout: {
        Args: Record<PropertyKey, never>
        Returns: Json
      }
      lquery_in: {
        Args: { "": unknown }
        Returns: unknown
      }
      lquery_out: {
        Args: { "": unknown }
        Returns: unknown
      }
      lquery_recv: {
        Args: { "": unknown }
        Returns: unknown
      }
      lquery_send: {
        Args: { "": unknown }
        Returns: string
      }
      ltree_compress: {
        Args: { "": unknown }
        Returns: unknown
      }
      ltree_decompress: {
        Args: { "": unknown }
        Returns: unknown
      }
      ltree_gist_in: {
        Args: { "": unknown }
        Returns: unknown
      }
      ltree_gist_options: {
        Args: { "": unknown }
        Returns: undefined
      }
      ltree_gist_out: {
        Args: { "": unknown }
        Returns: unknown
      }
      ltree_in: {
        Args: { "": unknown }
        Returns: unknown
      }
      ltree_out: {
        Args: { "": unknown }
        Returns: unknown
      }
      ltree_recv: {
        Args: { "": unknown }
        Returns: unknown
      }
      ltree_send: {
        Args: { "": unknown }
        Returns: string
      }
      ltree2text: {
        Args: { "": unknown }
        Returns: string
      }
      ltxtq_in: {
        Args: { "": unknown }
        Returns: unknown
      }
      ltxtq_out: {
        Args: { "": unknown }
        Returns: unknown
      }
      ltxtq_recv: {
        Args: { "": unknown }
        Returns: unknown
      }
      ltxtq_send: {
        Args: { "": unknown }
        Returns: string
      }
      nlevel: {
        Args: { "": unknown }
        Returns: number
      }
      notes_for_unit: {
        Args: {
          parent_establishment_id: number
          parent_legal_unit_id: number
          parent_enterprise_id: number
          parent_enterprise_group_id: number
        }
        Returns: Json
      }
      pg_stat_monitor_internal: {
        Args: { showtext: boolean }
        Returns: Record<string, unknown>[]
      }
      pg_stat_monitor_reset: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      pg_stat_monitor_version: {
        Args: Record<PropertyKey, never>
        Returns: string
      }
      pg_stat_statements: {
        Args: { showtext: boolean }
        Returns: Record<string, unknown>[]
      }
      pg_stat_statements_info: {
        Args: Record<PropertyKey, never>
        Returns: Record<string, unknown>
      }
      pg_stat_statements_reset: {
        Args: {
          userid?: unknown
          dbid?: unknown
          queryid?: number
          minmax_only?: boolean
        }
        Returns: string
      }
      pgp_armor_headers: {
        Args: { "": string }
        Returns: Record<string, unknown>[]
      }
      pgp_key_id: {
        Args: { "": string }
        Returns: string
      }
      pgsm_create_11_view: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      pgsm_create_13_view: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      pgsm_create_14_view: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      pgsm_create_15_view: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      pgsm_create_17_view: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      pgsm_create_view: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      plpgsql_check_function: {
        Args:
          | {
              name: string
              relid?: unknown
              format?: string
              fatal_errors?: boolean
              other_warnings?: boolean
              performance_warnings?: boolean
              extra_warnings?: boolean
              security_warnings?: boolean
              compatibility_warnings?: boolean
              oldtable?: unknown
              newtable?: unknown
              anyelememttype?: unknown
              anyenumtype?: unknown
              anyrangetype?: unknown
              anycompatibletype?: unknown
              anycompatiblerangetype?: unknown
              without_warnings?: boolean
              all_warnings?: boolean
              use_incomment_options?: boolean
              incomment_options_usage_warning?: boolean
              constant_tracing?: boolean
            }
          | {
              funcoid: unknown
              relid?: unknown
              format?: string
              fatal_errors?: boolean
              other_warnings?: boolean
              performance_warnings?: boolean
              extra_warnings?: boolean
              security_warnings?: boolean
              compatibility_warnings?: boolean
              oldtable?: unknown
              newtable?: unknown
              anyelememttype?: unknown
              anyenumtype?: unknown
              anyrangetype?: unknown
              anycompatibletype?: unknown
              anycompatiblerangetype?: unknown
              without_warnings?: boolean
              all_warnings?: boolean
              use_incomment_options?: boolean
              incomment_options_usage_warning?: boolean
              constant_tracing?: boolean
            }
        Returns: string[]
      }
      plpgsql_check_function_tb: {
        Args:
          | {
              funcoid: unknown
              relid?: unknown
              fatal_errors?: boolean
              other_warnings?: boolean
              performance_warnings?: boolean
              extra_warnings?: boolean
              security_warnings?: boolean
              compatibility_warnings?: boolean
              oldtable?: unknown
              newtable?: unknown
              anyelememttype?: unknown
              anyenumtype?: unknown
              anyrangetype?: unknown
              anycompatibletype?: unknown
              anycompatiblerangetype?: unknown
              without_warnings?: boolean
              all_warnings?: boolean
              use_incomment_options?: boolean
              incomment_options_usage_warning?: boolean
              constant_tracing?: boolean
            }
          | {
              name: string
              relid?: unknown
              fatal_errors?: boolean
              other_warnings?: boolean
              performance_warnings?: boolean
              extra_warnings?: boolean
              security_warnings?: boolean
              compatibility_warnings?: boolean
              oldtable?: unknown
              newtable?: unknown
              anyelememttype?: unknown
              anyenumtype?: unknown
              anyrangetype?: unknown
              anycompatibletype?: unknown
              anycompatiblerangetype?: unknown
              without_warnings?: boolean
              all_warnings?: boolean
              use_incomment_options?: boolean
              incomment_options_usage_warning?: boolean
              constant_tracing?: boolean
            }
        Returns: {
          functionid: unknown
          lineno: number
          statement: string
          sqlstate: string
          message: string
          detail: string
          hint: string
          level: string
          position: number
          query: string
          context: string
        }[]
      }
      plpgsql_check_pragma: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      plpgsql_check_profiler: {
        Args: { enable?: boolean }
        Returns: boolean
      }
      plpgsql_check_tracer: {
        Args: { enable?: boolean; verbosity?: string }
        Returns: boolean
      }
      plpgsql_coverage_branches: {
        Args: { funcoid: unknown } | { name: string }
        Returns: number
      }
      plpgsql_coverage_statements: {
        Args: { name: string } | { funcoid: unknown }
        Returns: number
      }
      plpgsql_profiler_function_statements_tb: {
        Args: { name: string } | { funcoid: unknown }
        Returns: {
          stmtid: number
          parent_stmtid: number
          parent_note: string
          block_num: number
          lineno: number
          queryid: number
          exec_stmts: number
          exec_stmts_err: number
          total_time: number
          avg_time: number
          max_time: number
          processed_rows: number
          stmtname: string
        }[]
      }
      plpgsql_profiler_function_tb: {
        Args: { funcoid: unknown } | { name: string }
        Returns: {
          lineno: number
          stmt_lineno: number
          queryids: number[]
          cmds_on_row: number
          exec_stmts: number
          exec_stmts_err: number
          total_time: number
          avg_time: number
          max_time: number[]
          processed_rows: number[]
          source: string
        }[]
      }
      plpgsql_profiler_functions_all: {
        Args: Record<PropertyKey, never>
        Returns: {
          funcoid: unknown
          exec_count: number
          exec_stmts_err: number
          total_time: number
          avg_time: number
          stddev_time: number
          min_time: number
          max_time: number
        }[]
      }
      plpgsql_profiler_install_fake_queryid_hook: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      plpgsql_profiler_remove_fake_queryid_hook: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      plpgsql_profiler_reset: {
        Args: { funcoid: unknown }
        Returns: undefined
      }
      plpgsql_profiler_reset_all: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      plpgsql_show_dependency_tb: {
        Args:
          | {
              funcoid: unknown
              relid?: unknown
              anyelememttype?: unknown
              anyenumtype?: unknown
              anyrangetype?: unknown
              anycompatibletype?: unknown
              anycompatiblerangetype?: unknown
            }
          | {
              fnname: string
              relid?: unknown
              anyelememttype?: unknown
              anyenumtype?: unknown
              anyrangetype?: unknown
              anycompatibletype?: unknown
              anycompatiblerangetype?: unknown
            }
        Returns: {
          type: string
          oid: unknown
          schema: string
          name: string
          params: string
        }[]
      }
      range: {
        Args: Record<PropertyKey, never>
        Returns: string[]
      }
      refresh: {
        Args: Record<PropertyKey, never>
        Returns: Json
      }
      region_hierarchy: {
        Args: { region_id: number }
        Returns: Json
      }
      region_used_derive: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      relevant_statistical_units: {
        Args: {
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          unit_id: number
          valid_on?: string
        }
        Returns: {
          activity_category_paths: unknown[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          email_address: string | null
          excluded_enterprise_ids: number[] | null
          excluded_establishment_ids: number[] | null
          excluded_legal_unit_ids: number[] | null
          external_idents: Json | null
          fax_number: string | null
          has_legal_unit: boolean | null
          include_unit_in_reports: boolean | null
          included_enterprise_count: number | null
          included_enterprise_ids: number[] | null
          included_establishment_count: number | null
          included_establishment_ids: number[] | null
          included_legal_unit_count: number | null
          included_legal_unit_ids: number[] | null
          invalid_codes: Json | null
          landline: string | null
          last_edit_at: string | null
          last_edit_by_user_id: number | null
          last_edit_comment: string | null
          legal_form_code: string | null
          legal_form_id: number | null
          legal_form_name: string | null
          mobile_number: string | null
          name: string | null
          phone_number: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_altitude: number | null
          physical_country_id: number | null
          physical_country_iso_2: string | null
          physical_latitude: number | null
          physical_longitude: number | null
          physical_postcode: string | null
          physical_postplace: string | null
          physical_region_code: string | null
          physical_region_id: number | null
          physical_region_path: unknown | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_altitude: number | null
          postal_country_id: number | null
          postal_country_iso_2: string | null
          postal_latitude: number | null
          postal_longitude: number | null
          postal_postcode: string | null
          postal_postplace: string | null
          postal_region_code: string | null
          postal_region_id: number | null
          postal_region_path: unknown | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: unknown | null
          related_enterprise_ids: number[] | null
          related_establishment_ids: number[] | null
          related_legal_unit_ids: number[] | null
          search: unknown | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: unknown | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: unknown | null
          stats: Json | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          tag_paths: unknown[] | null
          unit_id: number | null
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
          web_address: string | null
        }[]
      }
      remove_ephemeral_data_from_hierarchy: {
        Args: { data: Json }
        Returns: Json
      }
      reset: {
        Args: {
          confirmed: boolean
          scope: Database["public"]["Enums"]["reset_scope"]
        }
        Returns: Json
      }
      revoke_role: {
        Args: { user_sub: string }
        Returns: boolean
      }
      revoke_session: {
        Args: { refresh_session_jti: string }
        Returns: boolean
      }
      sector_hierarchy: {
        Args: { sector_id: number }
        Returns: Json
      }
      sector_used_derive: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      set_limit: {
        Args: { "": number }
        Returns: number
      }
      set_primary_establishment_for_legal_unit: {
        Args: {
          establishment_id: number
          valid_from_param?: string
          valid_to_param?: string
        }
        Returns: Json
      }
      set_primary_legal_unit_for_enterprise: {
        Args: {
          legal_unit_id: number
          valid_from_param?: string
          valid_to_param?: string
        }
        Returns: Json
      }
      show_limit: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      show_trgm: {
        Args: { "": string }
        Returns: string[]
      }
      sign: {
        Args: { payload: Json; secret: string; algorithm?: string }
        Returns: string
      }
      stat_for_unit_hierarchy: {
        Args: {
          parent_establishment_id?: number
          parent_legal_unit_id?: number
          valid_on?: string
        }
        Returns: Json
      }
      statistical_history_derive: {
        Args: { valid_after?: string; valid_to?: string }
        Returns: undefined
      }
      statistical_history_drilldown: {
        Args: {
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          resolution?: Database["public"]["Enums"]["history_resolution"]
          year?: number
          region_path?: unknown
          activity_category_path?: unknown
          sector_path?: unknown
          status_id?: number
          legal_form_id?: number
          country_id?: number
          year_min?: number
          year_max?: number
        }
        Returns: Json
      }
      statistical_history_facet_derive: {
        Args: { valid_after?: string; valid_to?: string }
        Returns: undefined
      }
      statistical_unit_details: {
        Args: {
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          unit_id: number
          valid_on?: string
        }
        Returns: Json
      }
      statistical_unit_enterprise_id: {
        Args: {
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          unit_id: number
          valid_on?: string
        }
        Returns: number
      }
      statistical_unit_facet_derive: {
        Args: { valid_after?: string; valid_to?: string }
        Returns: undefined
      }
      statistical_unit_facet_drilldown: {
        Args: {
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          region_path?: unknown
          activity_category_path?: unknown
          sector_path?: unknown
          status_id?: number
          legal_form_id?: number
          country_id?: number
          valid_on?: string
        }
        Returns: Json
      }
      statistical_unit_hierarchy: {
        Args: {
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          unit_id: number
          scope?: Database["public"]["Enums"]["hierarchy_scope"]
          valid_on?: string
          strip_nulls?: boolean
        }
        Returns: Json
      }
      statistical_unit_refresh: {
        Args: {
          p_establishment_ids?: number[]
          p_legal_unit_ids?: number[]
          p_enterprise_ids?: number[]
          p_valid_after?: string
          p_valid_to?: string
        }
        Returns: undefined
      }
      statistical_unit_stats: {
        Args: {
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          unit_id: number
          valid_on?: string
        }
        Returns: Database["public"]["CompositeTypes"]["statistical_unit_stats"][]
      }
      statistical_unit_tree: {
        Args: {
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          unit_id: number
          valid_on?: string
        }
        Returns: Json
      }
      status_hierarchy: {
        Args: { status_id: number }
        Returns: Json
      }
      tag_for_unit_hierarchy: {
        Args: {
          parent_establishment_id?: number
          parent_legal_unit_id?: number
          parent_enterprise_id?: number
          parent_enterprise_group_id?: number
        }
        Returns: Json
      }
      text_to_bytea: {
        Args: { data: string }
        Returns: string
      }
      text2ltree: {
        Args: { "": string }
        Returns: unknown
      }
      timeline_enterprise_refresh: {
        Args: { p_valid_after?: string; p_valid_to?: string }
        Returns: undefined
      }
      timeline_establishment_refresh: {
        Args: { p_valid_after?: string; p_valid_to?: string }
        Returns: undefined
      }
      timeline_legal_unit_refresh: {
        Args: { p_valid_after?: string; p_valid_to?: string }
        Returns: undefined
      }
      timesegments_refresh: {
        Args: { p_valid_after?: string; p_valid_to?: string }
        Returns: undefined
      }
      tri_fkey_check: {
        Args: {
          from_table: string
          fk_column: string
          from_range_column: string
          to_table: string
          pk_column: string
          to_range_column: string
          fk_val: number
          from_range: unknown
          updating: boolean
        }
        Returns: boolean
      }
      tri_fkey_restrict: {
        Args: {
          from_table: string
          fk_column: string
          from_range_column: string
          to_table: string
          pk_column: string
          to_range_column: string
          old_pk_val: number
          old_pk_range: unknown
        }
        Returns: boolean
      }
      try_cast_double: {
        Args: { inp: string }
        Returns: number
      }
      unit_size_hierarchy: {
        Args: { unit_size_id: number }
        Returns: Json
      }
      url_decode: {
        Args: { data: string }
        Returns: string
      }
      url_encode: {
        Args: { data: string }
        Returns: string
      }
      urlencode: {
        Args: { string: string } | { data: Json } | { string: string }
        Returns: string
      }
      user_create: {
        Args: {
          p_email: string
          p_statbus_role: Database["public"]["Enums"]["statbus_role"]
          p_password?: string
        }
        Returns: {
          email: string
          password: string
        }[]
      }
      user_update_role: {
        Args: {
          p_email: string
          p_statbus_role: Database["public"]["Enums"]["statbus_role"]
        }
        Returns: undefined
      }
      verify: {
        Args: { token: string; secret: string; algorithm?: string }
        Returns: {
          header: Json
          payload: Json
          valid: boolean
        }[]
      }
      websearch_to_wildcard_tsquery: {
        Args: { query: string }
        Returns: unknown
      }
    }
    Enums: {
      activity_category_code_behaviour: "digits" | "dot_after_two_digits"
      activity_type: "primary" | "secondary" | "ancilliary"
      hierarchy_scope: "all" | "tree" | "details"
      history_resolution: "year" | "year-month"
      import_data_state: "pending" | "importing" | "imported" | "error"
      import_job_state:
        | "waiting_for_upload"
        | "upload_completed"
        | "preparing_data"
        | "analysing_data"
        | "waiting_for_review"
        | "approved"
        | "rejected"
        | "importing_data"
        | "finished"
      import_source_expression: "now" | "default"
      location_type: "physical" | "postal"
      person_sex: "Male" | "Female"
      relative_period_code:
        | "today"
        | "year_curr"
        | "year_prev"
        | "year_curr_only"
        | "year_prev_only"
        | "start_of_week_curr"
        | "stop_of_week_prev"
        | "start_of_week_prev"
        | "start_of_month_curr"
        | "stop_of_month_prev"
        | "start_of_month_prev"
        | "start_of_quarter_curr"
        | "stop_of_quarter_prev"
        | "start_of_quarter_prev"
        | "start_of_semester_curr"
        | "stop_of_semester_prev"
        | "start_of_semester_prev"
        | "start_of_year_curr"
        | "stop_of_year_prev"
        | "start_of_year_prev"
        | "start_of_quinquennial_curr"
        | "stop_of_quinquennial_prev"
        | "start_of_quinquennial_prev"
        | "start_of_decade_curr"
        | "stop_of_decade_prev"
        | "start_of_decade_prev"
      relative_period_scope: "input_and_query" | "query" | "input"
      reset_scope: "data" | "getting-started" | "all"
      stat_frequency:
        | "daily"
        | "weekly"
        | "biweekly"
        | "monthly"
        | "bimonthly"
        | "quarterly"
        | "semesterly"
        | "yearly"
      stat_type: "int" | "float" | "string" | "bool"
      statbus_role:
        | "admin_user"
        | "regular_user"
        | "restricted_user"
        | "external_user"
      statistical_unit_type:
        | "establishment"
        | "legal_unit"
        | "enterprise"
        | "enterprise_group"
      tag_type: "custom" | "system"
      time_context_type: "relative_period" | "tag"
    }
    CompositeTypes: {
      http_header: {
        field: string | null
        value: string | null
      }
      http_request: {
        method: unknown | null
        uri: string | null
        headers: Database["public"]["CompositeTypes"]["http_header"][] | null
        content_type: string | null
        content: string | null
      }
      http_response: {
        status: number | null
        content_type: string | null
        headers: Database["public"]["CompositeTypes"]["http_header"][] | null
        content: string | null
      }
      statistical_unit_stats: {
        unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
        unit_id: number | null
        valid_from: string | null
        valid_to: string | null
        stats: Json | null
        stats_summary: Json | null
      }
    }
  }
}

type DefaultSchema = Database[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof Database },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof Database
  }
    ? keyof (Database[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        Database[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof Database }
  ? (Database[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      Database[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof Database },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof Database
  }
    ? keyof Database[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof Database }
  ? Database[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof Database },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof Database
  }
    ? keyof Database[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof Database }
  ? Database[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof Database },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof Database
  }
    ? keyof Database[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof Database }
  ? Database[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof Database },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof Database
  }
    ? keyof Database[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends { schema: keyof Database }
  ? Database[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      activity_category_code_behaviour: ["digits", "dot_after_two_digits"],
      activity_type: ["primary", "secondary", "ancilliary"],
      hierarchy_scope: ["all", "tree", "details"],
      history_resolution: ["year", "year-month"],
      import_data_state: ["pending", "importing", "imported", "error"],
      import_job_state: [
        "waiting_for_upload",
        "upload_completed",
        "preparing_data",
        "analysing_data",
        "waiting_for_review",
        "approved",
        "rejected",
        "importing_data",
        "finished",
      ],
      import_source_expression: ["now", "default"],
      location_type: ["physical", "postal"],
      person_sex: ["Male", "Female"],
      relative_period_code: [
        "today",
        "year_curr",
        "year_prev",
        "year_curr_only",
        "year_prev_only",
        "start_of_week_curr",
        "stop_of_week_prev",
        "start_of_week_prev",
        "start_of_month_curr",
        "stop_of_month_prev",
        "start_of_month_prev",
        "start_of_quarter_curr",
        "stop_of_quarter_prev",
        "start_of_quarter_prev",
        "start_of_semester_curr",
        "stop_of_semester_prev",
        "start_of_semester_prev",
        "start_of_year_curr",
        "stop_of_year_prev",
        "start_of_year_prev",
        "start_of_quinquennial_curr",
        "stop_of_quinquennial_prev",
        "start_of_quinquennial_prev",
        "start_of_decade_curr",
        "stop_of_decade_prev",
        "start_of_decade_prev",
      ],
      relative_period_scope: ["input_and_query", "query", "input"],
      reset_scope: ["data", "getting-started", "all"],
      stat_frequency: [
        "daily",
        "weekly",
        "biweekly",
        "monthly",
        "bimonthly",
        "quarterly",
        "semesterly",
        "yearly",
      ],
      stat_type: ["int", "float", "string", "bool"],
      statbus_role: [
        "admin_user",
        "regular_user",
        "restricted_user",
        "external_user",
      ],
      statistical_unit_type: [
        "establishment",
        "legal_unit",
        "enterprise",
        "enterprise_group",
      ],
      tag_type: ["custom", "system"],
      time_context_type: ["relative_period", "tag"],
    },
  },
} as const

