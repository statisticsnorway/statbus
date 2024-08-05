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
          establishment_id: number | null
          id: number
          legal_unit_id: number | null
          type: Database["public"]["Enums"]["activity_type"]
          updated_at: string
          updated_by_user_id: number
          valid_after: string
          valid_from: string
          valid_to: string
        }
        Insert: {
          category_id: number
          establishment_id?: number | null
          id?: number
          legal_unit_id?: number | null
          type: Database["public"]["Enums"]["activity_type"]
          updated_at?: string
          updated_by_user_id: number
          valid_after?: string
          valid_from?: string
          valid_to?: string
        }
        Update: {
          category_id?: number
          establishment_id?: number | null
          id?: number
          legal_unit_id?: number | null
          type?: Database["public"]["Enums"]["activity_type"]
          updated_at?: string
          updated_by_user_id?: number
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
            referencedRelation: "activity_category_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_updated_by_user_id_fkey"
            columns: ["updated_by_user_id"]
            isOneToOne: false
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          },
        ]
      }
      activity_category: {
        Row: {
          active: boolean
          code: string | null
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
          code?: string | null
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
          code?: string | null
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
            referencedRelation: "activity_category_used"
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
      activity_category_role: {
        Row: {
          activity_category_id: number
          id: number
          role_id: number
        }
        Insert: {
          activity_category_id: number
          id?: never
          role_id: number
        }
        Update: {
          activity_category_id?: number
          id?: never
          role_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "activity_category_role_activity_category_id_fkey"
            columns: ["activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_role_activity_category_id_fkey"
            columns: ["activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_role_activity_category_id_fkey"
            columns: ["activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_role_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "statbus_role"
            referencedColumns: ["id"]
          },
        ]
      }
      activity_category_standard: {
        Row: {
          code: string
          id: number
          name: string
          obsolete: boolean
        }
        Insert: {
          code: string
          id?: never
          name: string
          obsolete?: boolean
        }
        Update: {
          code?: string
          id?: never
          name?: string
          obsolete?: boolean
        }
        Relationships: []
      }
      analysis_log: {
        Row: {
          analysis_queue_id: number
          enterprise_group_id: number | null
          enterprise_id: number | null
          error_values: string | null
          establishment_id: number | null
          id: number
          issued_at: string
          legal_unit_id: number | null
          resolved_at: string | null
          summary_messages: string | null
        }
        Insert: {
          analysis_queue_id: number
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          error_values?: string | null
          establishment_id?: number | null
          id?: never
          issued_at: string
          legal_unit_id?: number | null
          resolved_at?: string | null
          summary_messages?: string | null
        }
        Update: {
          analysis_queue_id?: number
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          error_values?: string | null
          establishment_id?: number | null
          id?: never
          issued_at?: string
          legal_unit_id?: number | null
          resolved_at?: string | null
          summary_messages?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "analysis_log_analysis_queue_id_fkey"
            columns: ["analysis_queue_id"]
            isOneToOne: false
            referencedRelation: "analysis_queue"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "analysis_log_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "enterprise"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "analysis_log_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise"
            referencedColumns: ["enterprise_id"]
          },
        ]
      }
      analysis_queue: {
        Row: {
          comment: string | null
          id: number
          server_end_period: string | null
          server_start_period: string | null
          user_end_period: string
          user_id: number
          user_start_period: string
        }
        Insert: {
          comment?: string | null
          id?: never
          server_end_period?: string | null
          server_start_period?: string | null
          user_end_period: string
          user_id: number
          user_start_period: string
        }
        Update: {
          comment?: string | null
          id?: never
          server_end_period?: string | null
          server_start_period?: string | null
          user_end_period?: string
          user_id?: number
          user_start_period?: string
        }
        Relationships: [
          {
            foreignKeyName: "analysis_queue_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          },
        ]
      }
      country: {
        Row: {
          active: boolean
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
      custom_analysis_check: {
        Row: {
          id: number
          name: string | null
          query: string | null
          target_unit_types: string | null
        }
        Insert: {
          id?: never
          name?: string | null
          query?: string | null
          target_unit_types?: string | null
        }
        Update: {
          id?: never
          name?: string | null
          query?: string | null
          target_unit_types?: string | null
        }
        Relationships: []
      }
      data_source: {
        Row: {
          active: boolean
          code: string
          custom: boolean
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          custom: boolean
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          custom?: boolean
          id?: never
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      enterprise: {
        Row: {
          active: boolean
          edit_by_user_id: string
          edit_comment: string | null
          id: number
          notes: string | null
          short_name: string | null
          stat_ident: string | null
        }
        Insert: {
          active?: boolean
          edit_by_user_id: string
          edit_comment?: string | null
          id?: never
          notes?: string | null
          short_name?: string | null
          stat_ident?: string | null
        }
        Update: {
          active?: boolean
          edit_by_user_id?: string
          edit_comment?: string | null
          id?: never
          notes?: string | null
          short_name?: string | null
          stat_ident?: string | null
        }
        Relationships: []
      }
      enterprise_group: {
        Row: {
          active: boolean
          contact_person: string | null
          created_at: string
          data_source_id: number | null
          edit_by_user_id: number
          edit_comment: string | null
          email_address: string | null
          enterprise_group_type_id: number | null
          external_ident: string | null
          external_ident_type: string | null
          foreign_participation_id: number | null
          id: number
          name: string | null
          notes: string | null
          reorg_date: string | null
          reorg_references: string | null
          reorg_type_id: number | null
          short_name: string | null
          stat_ident: string | null
          telephone_no: string | null
          unit_size_id: number | null
          valid_after: string
          valid_from: string
          valid_to: string
          web_address: string | null
        }
        Insert: {
          active?: boolean
          contact_person?: string | null
          created_at?: string
          data_source_id?: number | null
          edit_by_user_id: number
          edit_comment?: string | null
          email_address?: string | null
          enterprise_group_type_id?: number | null
          external_ident?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          id?: number
          name?: string | null
          notes?: string | null
          reorg_date?: string | null
          reorg_references?: string | null
          reorg_type_id?: number | null
          short_name?: string | null
          stat_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
          web_address?: string | null
        }
        Update: {
          active?: boolean
          contact_person?: string | null
          created_at?: string
          data_source_id?: number | null
          edit_by_user_id?: number
          edit_comment?: string | null
          email_address?: string | null
          enterprise_group_type_id?: number | null
          external_ident?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          id?: number
          name?: string | null
          notes?: string | null
          reorg_date?: string | null
          reorg_references?: string | null
          reorg_type_id?: number | null
          short_name?: string | null
          stat_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
          web_address?: string | null
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
            referencedRelation: "data_source_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_system"
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
            referencedRelation: "enterprise_group_type_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_enterprise_group_type_id_fkey"
            columns: ["enterprise_group_type_id"]
            isOneToOne: false
            referencedRelation: "enterprise_group_type_system"
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
            referencedRelation: "foreign_participation_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_system"
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
            referencedRelation: "reorg_type_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_system"
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
            referencedRelation: "unit_size_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "enterprise_group_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_system"
            referencedColumns: ["id"]
          },
        ]
      }
      enterprise_group_role: {
        Row: {
          active: boolean
          code: string
          custom: boolean
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          custom: boolean
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
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
          custom: boolean
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          custom: boolean
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
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
          by_tag_id: number | null
          by_tag_id_unique_ident: string | null
          data_source_id: number | null
          death_date: string | null
          edit_by_user_id: string
          edit_comment: string | null
          email_address: string | null
          enterprise_id: number | null
          external_ident: string | null
          external_ident_type: string | null
          free_econ_zone: boolean | null
          id: number
          invalid_codes: Json | null
          legal_unit_id: number | null
          name: string | null
          notes: string | null
          parent_org_link: number | null
          primary_for_legal_unit: boolean | null
          reorg_date: string | null
          reorg_references: number | null
          reorg_type_id: number | null
          sector_id: number | null
          seen_in_import_at: string | null
          short_name: string | null
          stat_ident: string | null
          tax_ident: string | null
          telephone_no: string | null
          unit_size_id: number | null
          valid_after: string
          valid_from: string
          valid_to: string
          web_address: string | null
        }
        Insert: {
          active?: boolean
          birth_date?: string | null
          by_tag_id?: number | null
          by_tag_id_unique_ident?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_by_user_id: string
          edit_comment?: string | null
          email_address?: string | null
          enterprise_id?: number | null
          external_ident?: string | null
          external_ident_type?: string | null
          free_econ_zone?: boolean | null
          id?: number
          invalid_codes?: Json | null
          legal_unit_id?: number | null
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          primary_for_legal_unit?: boolean | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_id?: number | null
          sector_id?: number | null
          seen_in_import_at?: string | null
          short_name?: string | null
          stat_ident?: string | null
          tax_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
          web_address?: string | null
        }
        Update: {
          active?: boolean
          birth_date?: string | null
          by_tag_id?: number | null
          by_tag_id_unique_ident?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_by_user_id?: string
          edit_comment?: string | null
          email_address?: string | null
          enterprise_id?: number | null
          external_ident?: string | null
          external_ident_type?: string | null
          free_econ_zone?: boolean | null
          id?: number
          invalid_codes?: Json | null
          legal_unit_id?: number | null
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          primary_for_legal_unit?: boolean | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_id?: number | null
          sector_id?: number | null
          seen_in_import_at?: string | null
          short_name?: string | null
          stat_ident?: string | null
          tax_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "establishment_by_tag_id_fkey"
            columns: ["by_tag_id"]
            isOneToOne: false
            referencedRelation: "tag"
            referencedColumns: ["id"]
          },
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
            referencedRelation: "data_source_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_system"
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
            referencedRelation: "timeline_enterprise"
            referencedColumns: ["enterprise_id"]
          },
          {
            foreignKeyName: "establishment_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_system"
            referencedColumns: ["id"]
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
            referencedRelation: "sector_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit"
            referencedColumns: ["sector_id"]
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
            referencedRelation: "unit_size_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_system"
            referencedColumns: ["id"]
          },
        ]
      }
      foreign_participation: {
        Row: {
          active: boolean
          code: string
          custom: boolean
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          custom: boolean
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          custom?: boolean
          id?: never
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      legal_form: {
        Row: {
          active: boolean
          code: string
          custom: boolean
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          custom: boolean
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          custom?: boolean
          id?: never
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      legal_unit: {
        Row: {
          active: boolean
          birth_date: string | null
          by_tag_id: number | null
          by_tag_id_unique_ident: string | null
          data_source_id: number | null
          death_date: string | null
          edit_by_user_id: string
          edit_comment: string | null
          email_address: string | null
          enterprise_id: number
          external_ident: string | null
          external_ident_type: string | null
          foreign_participation_id: number | null
          free_econ_zone: boolean | null
          id: number
          invalid_codes: Json | null
          legal_form_id: number | null
          name: string | null
          notes: string | null
          parent_org_link: number | null
          primary_for_enterprise: boolean
          reorg_date: string | null
          reorg_references: number | null
          reorg_type_id: number | null
          sector_id: number | null
          seen_in_import_at: string | null
          short_name: string | null
          stat_ident: string | null
          tax_ident: string | null
          telephone_no: string | null
          unit_size_id: number | null
          valid_after: string
          valid_from: string
          valid_to: string
          web_address: string | null
        }
        Insert: {
          active?: boolean
          birth_date?: string | null
          by_tag_id?: number | null
          by_tag_id_unique_ident?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_by_user_id: string
          edit_comment?: string | null
          email_address?: string | null
          enterprise_id: number
          external_ident?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          free_econ_zone?: boolean | null
          id?: number
          invalid_codes?: Json | null
          legal_form_id?: number | null
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          primary_for_enterprise: boolean
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_id?: number | null
          sector_id?: number | null
          seen_in_import_at?: string | null
          short_name?: string | null
          stat_ident?: string | null
          tax_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
          web_address?: string | null
        }
        Update: {
          active?: boolean
          birth_date?: string | null
          by_tag_id?: number | null
          by_tag_id_unique_ident?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_by_user_id?: string
          edit_comment?: string | null
          email_address?: string | null
          enterprise_id?: number
          external_ident?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          free_econ_zone?: boolean | null
          id?: number
          invalid_codes?: Json | null
          legal_form_id?: number | null
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          primary_for_enterprise?: boolean
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_id?: number | null
          sector_id?: number | null
          seen_in_import_at?: string | null
          short_name?: string | null
          stat_ident?: string | null
          tax_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_after?: string
          valid_from?: string
          valid_to?: string
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "legal_unit_by_tag_id_fkey"
            columns: ["by_tag_id"]
            isOneToOne: false
            referencedRelation: "tag"
            referencedColumns: ["id"]
          },
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
            referencedRelation: "data_source_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_system"
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
            referencedRelation: "timeline_enterprise"
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
            referencedRelation: "foreign_participation_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_system"
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
            referencedRelation: "legal_form_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise"
            referencedColumns: ["legal_form_id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit"
            referencedColumns: ["legal_form_id"]
          },
          {
            foreignKeyName: "legal_unit_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_system"
            referencedColumns: ["id"]
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
            referencedRelation: "sector_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit"
            referencedColumns: ["sector_id"]
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
            referencedRelation: "unit_size_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_system"
            referencedColumns: ["id"]
          },
        ]
      }
      location: {
        Row: {
          address_part1: string | null
          address_part2: string | null
          address_part3: string | null
          country_id: number
          establishment_id: number | null
          id: number
          latitude: number | null
          legal_unit_id: number | null
          longitude: number | null
          postal_code: string | null
          postal_place: string | null
          region_id: number | null
          type: Database["public"]["Enums"]["location_type"]
          updated_by_user_id: number
          valid_after: string
          valid_from: string
          valid_to: string
        }
        Insert: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          country_id: number
          establishment_id?: number | null
          id?: number
          latitude?: number | null
          legal_unit_id?: number | null
          longitude?: number | null
          postal_code?: string | null
          postal_place?: string | null
          region_id?: number | null
          type: Database["public"]["Enums"]["location_type"]
          updated_by_user_id: number
          valid_after?: string
          valid_from?: string
          valid_to?: string
        }
        Update: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          country_id?: number
          establishment_id?: number | null
          id?: number
          latitude?: number | null
          legal_unit_id?: number | null
          longitude?: number | null
          postal_code?: string | null
          postal_place?: string | null
          region_id?: number | null
          type?: Database["public"]["Enums"]["location_type"]
          updated_by_user_id?: number
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
            referencedRelation: "country_used"
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
            referencedRelation: "region_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_updated_by_user_id_fkey"
            columns: ["updated_by_user_id"]
            isOneToOne: false
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          },
        ]
      }
      person: {
        Row: {
          address: string | null
          birth_date: string | null
          country_id: number | null
          created_at: string
          family_name: string | null
          given_name: string | null
          id: number
          middle_name: string | null
          personal_ident: string | null
          phone_number_1: string | null
          phone_number_2: string | null
          sex: Database["public"]["Enums"]["person_sex"] | null
        }
        Insert: {
          address?: string | null
          birth_date?: string | null
          country_id?: number | null
          created_at?: string
          family_name?: string | null
          given_name?: string | null
          id?: never
          middle_name?: string | null
          personal_ident?: string | null
          phone_number_1?: string | null
          phone_number_2?: string | null
          sex?: Database["public"]["Enums"]["person_sex"] | null
        }
        Update: {
          address?: string | null
          birth_date?: string | null
          country_id?: number | null
          created_at?: string
          family_name?: string | null
          given_name?: string | null
          id?: never
          middle_name?: string | null
          personal_ident?: string | null
          phone_number_1?: string | null
          phone_number_2?: string | null
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
            referencedRelation: "country_used"
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
          establishment_id: number | null
          id: number
          legal_unit_id: number | null
          person_id: number
          person_type_id: number | null
        }
        Insert: {
          establishment_id?: number | null
          id?: never
          legal_unit_id?: number | null
          person_id: number
          person_type_id?: number | null
        }
        Update: {
          establishment_id?: number | null
          id?: never
          legal_unit_id?: number | null
          person_id?: number
          person_type_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "person_for_unit_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "person"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_for_unit_person_type_id_fkey"
            columns: ["person_type_id"]
            isOneToOne: false
            referencedRelation: "person_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_for_unit_person_type_id_fkey"
            columns: ["person_type_id"]
            isOneToOne: false
            referencedRelation: "person_type_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_for_unit_person_type_id_fkey"
            columns: ["person_type_id"]
            isOneToOne: false
            referencedRelation: "person_type_system"
            referencedColumns: ["id"]
          },
        ]
      }
      person_type: {
        Row: {
          active: boolean
          code: string
          custom: boolean
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          custom: boolean
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          custom?: boolean
          id?: never
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      postal_index: {
        Row: {
          archived: boolean
          id: number
          name: string | null
          name_language1: string | null
          name_language2: string | null
        }
        Insert: {
          archived?: boolean
          id?: never
          name?: string | null
          name_language1?: string | null
          name_language2?: string | null
        }
        Update: {
          archived?: boolean
          id?: never
          name?: string | null
          name_language1?: string | null
          name_language2?: string | null
        }
        Relationships: []
      }
      region: {
        Row: {
          code: string | null
          id: number
          label: string
          level: number | null
          name: string
          parent_id: number | null
          path: unknown
        }
        Insert: {
          code?: string | null
          id?: number
          label?: string
          level?: number | null
          name: string
          parent_id?: number | null
          path: unknown
        }
        Update: {
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
            referencedRelation: "region_used"
            referencedColumns: ["id"]
          },
        ]
      }
      region_role: {
        Row: {
          id: number
          region_id: number
          role_id: number
        }
        Insert: {
          id?: never
          region_id: number
          role_id: number
        }
        Update: {
          id?: never
          region_id?: number
          role_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "region_role_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "region"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "region_role_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "region_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "region_role_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "statbus_role"
            referencedColumns: ["id"]
          },
        ]
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
          custom: boolean
          description: string
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          custom: boolean
          description: string
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          custom?: boolean
          description?: string
          id?: never
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      report_tree: {
        Row: {
          archived: boolean
          id: number
          parent_node_id: number | null
          report_id: number | null
          report_url: string | null
          resource_group: string | null
          title: string | null
          type: string | null
        }
        Insert: {
          archived?: boolean
          id?: never
          parent_node_id?: number | null
          report_id?: number | null
          report_url?: string | null
          resource_group?: string | null
          title?: string | null
          type?: string | null
        }
        Update: {
          archived?: boolean
          id?: never
          parent_node_id?: number | null
          report_id?: number | null
          report_url?: string | null
          resource_group?: string | null
          title?: string | null
          type?: string | null
        }
        Relationships: []
      }
      sample_frame: {
        Row: {
          creation_date: string
          description: string | null
          editing_date: string | null
          fields: string
          file_path: string | null
          generated_date_time: string | null
          id: number
          name: string
          predicate: string
          status: number
          user_id: number | null
        }
        Insert: {
          creation_date: string
          description?: string | null
          editing_date?: string | null
          fields: string
          file_path?: string | null
          generated_date_time?: string | null
          id?: never
          name: string
          predicate: string
          status: number
          user_id?: number | null
        }
        Update: {
          creation_date?: string
          description?: string | null
          editing_date?: string | null
          fields?: string
          file_path?: string | null
          generated_date_time?: string | null
          id?: never
          name?: string
          predicate?: string
          status?: number
          user_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "sample_frame_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          },
        ]
      }
      sector: {
        Row: {
          active: boolean
          code: string | null
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
            foreignKeyName: "stat_for_unit_stat_definition_id_fkey"
            columns: ["stat_definition_id"]
            isOneToOne: false
            referencedRelation: "stat_definition"
            referencedColumns: ["id"]
          },
        ]
      }
      statbus_role: {
        Row: {
          description: string | null
          id: number
          name: string
          type: Database["public"]["Enums"]["statbus_role_type"]
        }
        Insert: {
          description?: string | null
          id?: never
          name: string
          type: Database["public"]["Enums"]["statbus_role_type"]
        }
        Update: {
          description?: string | null
          id?: never
          name?: string
          type?: Database["public"]["Enums"]["statbus_role_type"]
        }
        Relationships: []
      }
      statbus_user: {
        Row: {
          id: number
          role_id: number
          uuid: string
        }
        Insert: {
          id?: number
          role_id: number
          uuid: string
        }
        Update: {
          id?: number
          role_id?: number
          uuid?: string
        }
        Relationships: [
          {
            foreignKeyName: "statbus_user_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "statbus_role"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "statbus_user_uuid_fkey"
            columns: ["uuid"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
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
          enterprise_group_id: number | null
          enterprise_id: number | null
          establishment_id: number | null
          id: number
          legal_unit_id: number | null
          tag_id: number
          updated_by_user_id: number
        }
        Insert: {
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: never
          legal_unit_id?: number | null
          tag_id: number
          updated_by_user_id: number
        }
        Update: {
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: never
          legal_unit_id?: number | null
          tag_id?: number
          updated_by_user_id?: number
        }
        Relationships: [
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
            referencedRelation: "timeline_enterprise"
            referencedColumns: ["enterprise_id"]
          },
          {
            foreignKeyName: "tag_for_unit_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "tag"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tag_for_unit_updated_by_user_id_fkey"
            columns: ["updated_by_user_id"]
            isOneToOne: false
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          },
        ]
      }
      unit_size: {
        Row: {
          active: boolean
          code: string
          custom: boolean
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code: string
          custom: boolean
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
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
          description: string | null
          id: number | null
          label: string | null
          name: string | null
          parent_code: string | null
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
      activity_category_used: {
        Row: {
          code: string | null
          description: string | null
          id: number | null
          label: string | null
          name: string | null
          parent_code: string | null
          path: unknown | null
          standard_code: string | null
        }
        Relationships: []
      }
      activity_era: {
        Row: {
          category_id: number | null
          establishment_id: number | null
          id: number | null
          legal_unit_id: number | null
          type: Database["public"]["Enums"]["activity_type"] | null
          updated_at: string | null
          updated_by_user_id: number | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Insert: {
          category_id?: number | null
          establishment_id?: number | null
          id?: number | null
          legal_unit_id?: number | null
          type?: Database["public"]["Enums"]["activity_type"] | null
          updated_at?: string | null
          updated_by_user_id?: number | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Update: {
          category_id?: number | null
          establishment_id?: number | null
          id?: number | null
          legal_unit_id?: number | null
          type?: Database["public"]["Enums"]["activity_type"] | null
          updated_at?: string | null
          updated_by_user_id?: number | null
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
            referencedRelation: "activity_category_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_updated_by_user_id_fkey"
            columns: ["updated_by_user_id"]
            isOneToOne: false
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          },
        ]
      }
      country_used: {
        Row: {
          id: number | null
          iso_2: string | null
          name: string | null
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
      data_source_custom: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      data_source_system: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      enterprise_group_role_custom: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      enterprise_group_role_system: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      enterprise_group_type_custom: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      enterprise_group_type_system: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      establishment_brreg_view: {
        Row: {
          antallAnsatte: string | null
          "beliggenhetsadresse.adresse": string | null
          "beliggenhetsadresse.kommune": string | null
          "beliggenhetsadresse.kommunenummer": string | null
          "beliggenhetsadresse.land": string | null
          "beliggenhetsadresse.landkode": string | null
          "beliggenhetsadresse.postnummer": string | null
          "beliggenhetsadresse.poststed": string | null
          datoEierskifte: string | null
          frivilligMvaRegistrertBeskrivelser: string | null
          harRegistrertAntallAnsatte: string | null
          "hjelpeenhetskode.beskrivelse": string | null
          "hjelpeenhetskode.kode": string | null
          hjemmeside: string | null
          "naeringskode1.beskrivelse": string | null
          "naeringskode1.kode": string | null
          "naeringskode2.beskrivelse": string | null
          "naeringskode2.kode": string | null
          "naeringskode3.beskrivelse": string | null
          "naeringskode3.kode": string | null
          navn: string | null
          nedleggelsesdato: string | null
          oppstartsdato: string | null
          "organisasjonsform.beskrivelse": string | null
          "organisasjonsform.kode": string | null
          organisasjonsnummer: string | null
          overordnetEnhet: string | null
          "postadresse.adresse": string | null
          "postadresse.kommune": string | null
          "postadresse.kommunenummer": string | null
          "postadresse.land": string | null
          "postadresse.landkode": string | null
          "postadresse.postnummer": string | null
          "postadresse.poststed": string | null
          registreringsdatoIEnhetsregisteret: string | null
          registrertIMvaregisteret: string | null
        }
        Relationships: []
      }
      establishment_era: {
        Row: {
          active: boolean | null
          birth_date: string | null
          by_tag_id: number | null
          by_tag_id_unique_ident: string | null
          data_source_id: number | null
          death_date: string | null
          edit_by_user_id: string | null
          edit_comment: string | null
          email_address: string | null
          enterprise_id: number | null
          external_ident: string | null
          external_ident_type: string | null
          free_econ_zone: boolean | null
          id: number | null
          invalid_codes: Json | null
          legal_unit_id: number | null
          name: string | null
          notes: string | null
          parent_org_link: number | null
          primary_for_legal_unit: boolean | null
          reorg_date: string | null
          reorg_references: number | null
          reorg_type_id: number | null
          sector_id: number | null
          seen_in_import_at: string | null
          short_name: string | null
          stat_ident: string | null
          tax_ident: string | null
          telephone_no: string | null
          unit_size_id: number | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
          web_address: string | null
        }
        Insert: {
          active?: boolean | null
          birth_date?: string | null
          by_tag_id?: number | null
          by_tag_id_unique_ident?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_by_user_id?: string | null
          edit_comment?: string | null
          email_address?: string | null
          enterprise_id?: number | null
          external_ident?: string | null
          external_ident_type?: string | null
          free_econ_zone?: boolean | null
          id?: number | null
          invalid_codes?: Json | null
          legal_unit_id?: number | null
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          primary_for_legal_unit?: boolean | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_id?: number | null
          sector_id?: number | null
          seen_in_import_at?: string | null
          short_name?: string | null
          stat_ident?: string | null
          tax_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
          web_address?: string | null
        }
        Update: {
          active?: boolean | null
          birth_date?: string | null
          by_tag_id?: number | null
          by_tag_id_unique_ident?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_by_user_id?: string | null
          edit_comment?: string | null
          email_address?: string | null
          enterprise_id?: number | null
          external_ident?: string | null
          external_ident_type?: string | null
          free_econ_zone?: boolean | null
          id?: number | null
          invalid_codes?: Json | null
          legal_unit_id?: number | null
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          primary_for_legal_unit?: boolean | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_id?: number | null
          sector_id?: number | null
          seen_in_import_at?: string | null
          short_name?: string | null
          stat_ident?: string | null
          tax_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "establishment_by_tag_id_fkey"
            columns: ["by_tag_id"]
            isOneToOne: false
            referencedRelation: "tag"
            referencedColumns: ["id"]
          },
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
            referencedRelation: "data_source_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_system"
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
            referencedRelation: "timeline_enterprise"
            referencedColumns: ["enterprise_id"]
          },
          {
            foreignKeyName: "establishment_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_system"
            referencedColumns: ["id"]
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
            referencedRelation: "sector_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit"
            referencedColumns: ["sector_id"]
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
            referencedRelation: "unit_size_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_system"
            referencedColumns: ["id"]
          },
        ]
      }
      foreign_participation_custom: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      foreign_participation_system: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      import_establishment_current_for_legal_unit: {
        Row: {
          birth_date: string | null
          death_date: string | null
          employees: string | null
          legal_unit_tax_ident: string | null
          name: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_country_iso_2: string | null
          physical_postal_code: string | null
          physical_postal_place: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_country_iso_2: string | null
          postal_postal_code: string | null
          postal_postal_place: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          tag_path: string | null
          tax_ident: string | null
          turnover: string | null
        }
        Relationships: []
      }
      import_establishment_current_without_legal_unit: {
        Row: {
          birth_date: string | null
          death_date: string | null
          employees: string | null
          name: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_country_iso_2: string | null
          physical_postal_code: string | null
          physical_postal_place: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_country_iso_2: string | null
          postal_postal_code: string | null
          postal_postal_place: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          sector_code: string | null
          tag_path: string | null
          tax_ident: string | null
          turnover: string | null
        }
        Relationships: []
      }
      import_establishment_era: {
        Row: {
          birth_date: string | null
          death_date: string | null
          employees: string | null
          legal_unit_tax_ident: string | null
          name: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_country_iso_2: string | null
          physical_postal_code: string | null
          physical_postal_place: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_country_iso_2: string | null
          postal_postal_code: string | null
          postal_postal_place: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          sector_code: string | null
          tag_path: string | null
          tax_ident: string | null
          turnover: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Relationships: []
      }
      import_establishment_era_for_legal_unit: {
        Row: {
          birth_date: string | null
          death_date: string | null
          employees: string | null
          legal_unit_tax_ident: string | null
          name: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_country_iso_2: string | null
          physical_postal_code: string | null
          physical_postal_place: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_country_iso_2: string | null
          postal_postal_code: string | null
          postal_postal_place: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          tag_path: string | null
          tax_ident: string | null
          turnover: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Relationships: []
      }
      import_establishment_era_without_legal_unit: {
        Row: {
          birth_date: string | null
          death_date: string | null
          employees: string | null
          name: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_country_iso_2: string | null
          physical_postal_code: string | null
          physical_postal_place: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_country_iso_2: string | null
          postal_postal_code: string | null
          postal_postal_place: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          sector_code: string | null
          tag_path: string | null
          tax_ident: string | null
          turnover: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Relationships: []
      }
      import_legal_unit_current: {
        Row: {
          birth_date: string | null
          death_date: string | null
          legal_form_code: string | null
          name: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_country_iso_2: string | null
          physical_postal_code: string | null
          physical_postal_place: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_country_iso_2: string | null
          postal_postal_code: string | null
          postal_postal_place: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          sector_code: string | null
          tag_path: string | null
          tax_ident: string | null
        }
        Relationships: []
      }
      import_legal_unit_era: {
        Row: {
          birth_date: string | null
          death_date: string | null
          legal_form_code: string | null
          name: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_country_iso_2: string | null
          physical_postal_code: string | null
          physical_postal_place: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_country_iso_2: string | null
          postal_postal_code: string | null
          postal_postal_place: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          sector_code: string | null
          tag_path: string | null
          tax_ident: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Relationships: []
      }
      import_legal_unit_with_delete_current: {
        Row: {
          birth_date: string | null
          death_date: string | null
          legal_form_code: string | null
          name: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_country_iso_2: string | null
          physical_postal_code: string | null
          physical_postal_place: string | null
          physical_region_code: string | null
          physical_region_path: string | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_country_iso_2: string | null
          postal_postal_code: string | null
          postal_postal_place: string | null
          postal_region_code: string | null
          postal_region_path: string | null
          primary_activity_category_code: string | null
          secondary_activity_category_code: string | null
          sector_code: string | null
          tag_path: string | null
          tax_ident: string | null
        }
        Relationships: []
      }
      legal_form_available: {
        Row: {
          code: string | null
          custom: boolean | null
          name: string | null
        }
        Insert: {
          code?: string | null
          custom?: boolean | null
          name?: string | null
        }
        Update: {
          code?: string | null
          custom?: boolean | null
          name?: string | null
        }
        Relationships: []
      }
      legal_form_custom: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
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
      legal_form_system: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      legal_form_used: {
        Row: {
          code: string | null
          id: number | null
          name: string | null
        }
        Relationships: []
      }
      legal_unit_brreg_view: {
        Row: {
          aktivitet: string | null
          antallAnsatte: string | null
          "forretningsadresse.adresse": string | null
          "forretningsadresse.kommune": string | null
          "forretningsadresse.kommunenummer": string | null
          "forretningsadresse.land": string | null
          "forretningsadresse.landkode": string | null
          "forretningsadresse.postnummer": string | null
          "forretningsadresse.poststed": string | null
          frivilligMvaRegistrertBeskrivelser: string | null
          harRegistrertAntallAnsatte: string | null
          "hjelpeenhetskode.beskrivelse": string | null
          "hjelpeenhetskode.kode": string | null
          hjemmeside: string | null
          "institusjonellSektorkode.beskrivelse": string | null
          "institusjonellSektorkode.kode": string | null
          konkurs: string | null
          konkursdato: string | null
          maalform: string | null
          "naeringskode1.beskrivelse": string | null
          "naeringskode1.kode": string | null
          "naeringskode2.beskrivelse": string | null
          "naeringskode2.kode": string | null
          "naeringskode3.beskrivelse": string | null
          "naeringskode3.kode": string | null
          navn: string | null
          "organisasjonsform.beskrivelse": string | null
          "organisasjonsform.kode": string | null
          organisasjonsnummer: string | null
          overordnetEnhet: string | null
          "postadresse.adresse": string | null
          "postadresse.kommune": string | null
          "postadresse.kommunenummer": string | null
          "postadresse.land": string | null
          "postadresse.landkode": string | null
          "postadresse.postnummer": string | null
          "postadresse.poststed": string | null
          registreringsdatoenhetsregisteret: string | null
          registrertIForetaksregisteret: string | null
          registrertIFrivillighetsregisteret: string | null
          registrertIMvaRegisteret: string | null
          registrertIStiftelsesregisteret: string | null
          sisteInnsendteAarsregnskap: string | null
          stiftelsesdato: string | null
          tvangsavvikletPgaManglendeSlettingDato: string | null
          tvangsopplostPgaMangelfulltStyreDato: string | null
          tvangsopplostPgaManglendeDagligLederDato: string | null
          tvangsopplostPgaManglendeRegnskapDato: string | null
          tvangsopplostPgaManglendeRevisorDato: string | null
          underAvvikling: string | null
          underAvviklingDato: string | null
          underTvangsavviklingEllerTvangsopplosning: string | null
          vedtektsdato: string | null
          vedtektsfestetFormaal: string | null
        }
        Relationships: []
      }
      legal_unit_era: {
        Row: {
          active: boolean | null
          birth_date: string | null
          by_tag_id: number | null
          by_tag_id_unique_ident: string | null
          data_source_id: number | null
          death_date: string | null
          edit_by_user_id: string | null
          edit_comment: string | null
          email_address: string | null
          enterprise_id: number | null
          external_ident: string | null
          external_ident_type: string | null
          foreign_participation_id: number | null
          free_econ_zone: boolean | null
          id: number | null
          invalid_codes: Json | null
          legal_form_id: number | null
          name: string | null
          notes: string | null
          parent_org_link: number | null
          primary_for_enterprise: boolean | null
          reorg_date: string | null
          reorg_references: number | null
          reorg_type_id: number | null
          sector_id: number | null
          seen_in_import_at: string | null
          short_name: string | null
          stat_ident: string | null
          tax_ident: string | null
          telephone_no: string | null
          unit_size_id: number | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
          web_address: string | null
        }
        Insert: {
          active?: boolean | null
          birth_date?: string | null
          by_tag_id?: number | null
          by_tag_id_unique_ident?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_by_user_id?: string | null
          edit_comment?: string | null
          email_address?: string | null
          enterprise_id?: number | null
          external_ident?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          free_econ_zone?: boolean | null
          id?: number | null
          invalid_codes?: Json | null
          legal_form_id?: number | null
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          primary_for_enterprise?: boolean | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_id?: number | null
          sector_id?: number | null
          seen_in_import_at?: string | null
          short_name?: string | null
          stat_ident?: string | null
          tax_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
          web_address?: string | null
        }
        Update: {
          active?: boolean | null
          birth_date?: string | null
          by_tag_id?: number | null
          by_tag_id_unique_ident?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_by_user_id?: string | null
          edit_comment?: string | null
          email_address?: string | null
          enterprise_id?: number | null
          external_ident?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          free_econ_zone?: boolean | null
          id?: number | null
          invalid_codes?: Json | null
          legal_form_id?: number | null
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          primary_for_enterprise?: boolean | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_id?: number | null
          sector_id?: number | null
          seen_in_import_at?: string | null
          short_name?: string | null
          stat_ident?: string | null
          tax_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "legal_unit_by_tag_id_fkey"
            columns: ["by_tag_id"]
            isOneToOne: false
            referencedRelation: "tag"
            referencedColumns: ["id"]
          },
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
            referencedRelation: "data_source_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source_system"
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
            referencedRelation: "timeline_enterprise"
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
            referencedRelation: "foreign_participation_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_system"
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
            referencedRelation: "legal_form_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise"
            referencedColumns: ["legal_form_id"]
          },
          {
            foreignKeyName: "legal_unit_legal_form_id_fkey"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit"
            referencedColumns: ["legal_form_id"]
          },
          {
            foreignKeyName: "legal_unit_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_reorg_type_id_fkey"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_system"
            referencedColumns: ["id"]
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
            referencedRelation: "sector_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit"
            referencedColumns: ["sector_id"]
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
            referencedRelation: "unit_size_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_system"
            referencedColumns: ["id"]
          },
        ]
      }
      location_era: {
        Row: {
          address_part1: string | null
          address_part2: string | null
          address_part3: string | null
          country_id: number | null
          establishment_id: number | null
          id: number | null
          latitude: number | null
          legal_unit_id: number | null
          longitude: number | null
          postal_code: string | null
          postal_place: string | null
          region_id: number | null
          type: Database["public"]["Enums"]["location_type"] | null
          updated_by_user_id: number | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Insert: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          country_id?: number | null
          establishment_id?: number | null
          id?: number | null
          latitude?: number | null
          legal_unit_id?: number | null
          longitude?: number | null
          postal_code?: string | null
          postal_place?: string | null
          region_id?: number | null
          type?: Database["public"]["Enums"]["location_type"] | null
          updated_by_user_id?: number | null
          valid_after?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Update: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          country_id?: number | null
          establishment_id?: number | null
          id?: number | null
          latitude?: number | null
          legal_unit_id?: number | null
          longitude?: number | null
          postal_code?: string | null
          postal_place?: string | null
          region_id?: number | null
          type?: Database["public"]["Enums"]["location_type"] | null
          updated_by_user_id?: number | null
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
            referencedRelation: "country_used"
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
            referencedRelation: "region_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_updated_by_user_id_fkey"
            columns: ["updated_by_user_id"]
            isOneToOne: false
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          },
        ]
      }
      period_active: {
        Row: {
          code: Database["public"]["Enums"]["relative_period_code"] | null
          ident: string | null
          name_when_input: string | null
          name_when_query: string | null
          path: unknown | null
          scope: Database["public"]["Enums"]["relative_period_scope"] | null
          type: Database["public"]["Enums"]["period_type"] | null
          valid_from: string | null
          valid_on: string | null
          valid_to: string | null
        }
        Relationships: []
      }
      person_type_custom: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      person_type_system: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      region_7_levels_view: {
        Row: {
          "Constituency Code": string | null
          "Constituency Name": string | null
          "County Code": string | null
          "County Name": string | null
          "District Code": string | null
          "District Name": string | null
          "Parish Code": string | null
          "Parish Name": string | null
          "Regional Code": string | null
          "Regional Name": string | null
          "Subcounty Code": string | null
          "Subcounty Name": string | null
          "Village Code": string | null
          "Village Name": string | null
        }
        Relationships: []
      }
      region_upload: {
        Row: {
          name: string | null
          path: unknown | null
        }
        Insert: {
          name?: string | null
          path?: unknown | null
        }
        Update: {
          name?: string | null
          path?: unknown | null
        }
        Relationships: []
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
      reorg_type_custom: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
          description: string | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          description?: string | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
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
          active: boolean | null
          code: string | null
          custom: boolean | null
          description: string | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          description?: string | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          description?: string | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      sector_available: {
        Row: {
          custom: boolean | null
          description: string | null
          name: string | null
          path: unknown | null
        }
        Insert: {
          custom?: boolean | null
          description?: string | null
          name?: string | null
          path?: unknown | null
        }
        Update: {
          custom?: boolean | null
          description?: string | null
          name?: string | null
          path?: unknown | null
        }
        Relationships: []
      }
      sector_custom: {
        Row: {
          active: boolean | null
          code: string | null
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
      sector_system: {
        Row: {
          active: boolean | null
          code: string | null
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
      sector_used: {
        Row: {
          code: string | null
          id: number | null
          label: string | null
          name: string | null
          path: unknown | null
        }
        Relationships: []
      }
      stat_for_unit_era: {
        Row: {
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
            foreignKeyName: "stat_for_unit_stat_definition_id_fkey"
            columns: ["stat_definition_id"]
            isOneToOne: false
            referencedRelation: "stat_definition"
            referencedColumns: ["id"]
          },
        ]
      }
      statistical_history: {
        Row: {
          births: number | null
          count: number | null
          deaths: number | null
          employees: number | null
          legal_form_change_count: number | null
          month: number | null
          physical_country_change_count: number | null
          physical_region_change_count: number | null
          primary_activity_category_change_count: number | null
          secondary_activity_category_change_count: number | null
          sector_change_count: number | null
          turnover: number | null
          type: Database["public"]["Enums"]["statistical_history_type"] | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          year: number | null
        }
        Relationships: []
      }
      statistical_history_def: {
        Row: {
          births: number | null
          count: number | null
          deaths: number | null
          employees: number | null
          legal_form_change_count: number | null
          month: number | null
          physical_country_change_count: number | null
          physical_region_change_count: number | null
          primary_activity_category_change_count: number | null
          secondary_activity_category_change_count: number | null
          sector_change_count: number | null
          turnover: number | null
          type: Database["public"]["Enums"]["statistical_history_type"] | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          year: number | null
        }
        Relationships: []
      }
      statistical_history_facet: {
        Row: {
          births: number | null
          count: number | null
          deaths: number | null
          employees: number | null
          legal_form_change_count: number | null
          legal_form_id: number | null
          month: number | null
          physical_country_change_count: number | null
          physical_country_id: number | null
          physical_region_change_count: number | null
          physical_region_path: unknown | null
          primary_activity_category_change_count: number | null
          primary_activity_category_path: unknown | null
          secondary_activity_category_change_count: number | null
          secondary_activity_category_path: unknown | null
          sector_change_count: number | null
          sector_path: unknown | null
          turnover: number | null
          type: Database["public"]["Enums"]["statistical_history_type"] | null
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
          employees: number | null
          legal_form_change_count: number | null
          legal_form_id: number | null
          month: number | null
          physical_country_change_count: number | null
          physical_country_id: number | null
          physical_region_change_count: number | null
          physical_region_path: unknown | null
          primary_activity_category_change_count: number | null
          primary_activity_category_path: unknown | null
          secondary_activity_category_change_count: number | null
          secondary_activity_category_path: unknown | null
          sector_change_count: number | null
          sector_path: unknown | null
          turnover: number | null
          type: Database["public"]["Enums"]["statistical_history_type"] | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          year: number | null
        }
        Relationships: []
      }
      statistical_unit: {
        Row: {
          activity_category_paths: unknown[] | null
          birth_date: string | null
          by_tag_id: number | null
          by_tag_id_unique_ident: string | null
          death_date: string | null
          employees: number | null
          enterprise_count: number | null
          enterprise_ids: number[] | null
          establishment_count: number | null
          establishment_ids: number[] | null
          external_ident: string | null
          external_ident_type: string | null
          invalid_codes: Json | null
          legal_form_code: string | null
          legal_form_id: number | null
          legal_form_name: string | null
          legal_unit_count: number | null
          legal_unit_ids: number[] | null
          name: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_country_id: number | null
          physical_country_iso_2: string | null
          physical_postal_code: string | null
          physical_postal_place: string | null
          physical_region_id: number | null
          physical_region_path: unknown | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_country_id: number | null
          postal_country_iso_2: string | null
          postal_postal_code: string | null
          postal_postal_place: string | null
          postal_region_id: number | null
          postal_region_path: unknown | null
          primary_activity_category_id: number | null
          primary_activity_category_path: unknown | null
          search: unknown | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: unknown | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: unknown | null
          stat_ident: string | null
          tag_paths: unknown[] | null
          tax_ident: string | null
          turnover: number | null
          unit_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Relationships: []
      }
      statistical_unit_def: {
        Row: {
          activity_category_paths: unknown[] | null
          birth_date: string | null
          by_tag_id: number | null
          by_tag_id_unique_ident: string | null
          death_date: string | null
          employees: number | null
          enterprise_count: number | null
          enterprise_ids: number[] | null
          establishment_count: number | null
          establishment_ids: number[] | null
          external_ident: string | null
          external_ident_type: string | null
          invalid_codes: Json | null
          legal_form_code: string | null
          legal_form_id: number | null
          legal_form_name: string | null
          legal_unit_count: number | null
          legal_unit_ids: number[] | null
          name: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_country_id: number | null
          physical_country_iso_2: string | null
          physical_postal_code: string | null
          physical_postal_place: string | null
          physical_region_id: number | null
          physical_region_path: unknown | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_country_id: number | null
          postal_country_iso_2: string | null
          postal_postal_code: string | null
          postal_postal_place: string | null
          postal_region_id: number | null
          postal_region_path: unknown | null
          primary_activity_category_id: number | null
          primary_activity_category_path: unknown | null
          search: unknown | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: unknown | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: unknown | null
          stat_ident: string | null
          tag_paths: unknown[] | null
          tax_ident: string | null
          turnover: number | null
          unit_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Relationships: []
      }
      statistical_unit_facet: {
        Row: {
          count: number | null
          employees: number | null
          legal_form_id: number | null
          physical_country_id: number | null
          physical_region_path: unknown | null
          primary_activity_category_path: unknown | null
          sector_path: unknown | null
          turnover: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from: string | null
          valid_to: string | null
        }
        Relationships: []
      }
      timeline_enterprise: {
        Row: {
          activity_category_paths: unknown[] | null
          birth_date: string | null
          by_tag_id: number | null
          by_tag_id_unique_ident: string | null
          death_date: string | null
          employees: number | null
          enterprise_id: number | null
          establishment_ids: number[] | null
          external_ident: string | null
          external_ident_type: string | null
          invalid_codes: Json | null
          legal_form_code: string | null
          legal_form_id: number | null
          legal_form_name: string | null
          legal_unit_ids: number[] | null
          name: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_country_id: number | null
          physical_country_iso_2: string | null
          physical_postal_code: string | null
          physical_postal_place: string | null
          physical_region_id: number | null
          physical_region_path: unknown | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_country_id: number | null
          postal_country_iso_2: string | null
          postal_postal_code: string | null
          postal_postal_place: string | null
          postal_region_id: number | null
          postal_region_path: unknown | null
          primary_activity_category_id: number | null
          primary_activity_category_path: unknown | null
          search: unknown | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: unknown | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: unknown | null
          stat_ident: string | null
          tax_ident: string | null
          turnover: number | null
          unit_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Relationships: [
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
            referencedRelation: "activity_category"
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
            columns: ["primary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used"
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
            columns: ["secondary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_by_tag_id_fkey"
            columns: ["by_tag_id"]
            isOneToOne: false
            referencedRelation: "tag"
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
            referencedRelation: "country_used"
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
            referencedRelation: "country_used"
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
            referencedRelation: "region_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["postal_region_id"]
            isOneToOne: false
            referencedRelation: "region_used"
            referencedColumns: ["id"]
          },
        ]
      }
      timeline_establishment: {
        Row: {
          activity_category_paths: unknown[] | null
          birth_date: string | null
          by_tag_id: number | null
          by_tag_id_unique_ident: string | null
          death_date: string | null
          employees: number | null
          enterprise_id: number | null
          establishment_id: number | null
          external_ident: string | null
          external_ident_type: string | null
          invalid_codes: Json | null
          legal_form_code: string | null
          legal_form_id: number | null
          legal_form_name: string | null
          legal_unit_id: number | null
          name: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_country_id: number | null
          physical_country_iso_2: string | null
          physical_postal_code: string | null
          physical_postal_place: string | null
          physical_region_id: number | null
          physical_region_path: unknown | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_country_id: number | null
          postal_country_iso_2: string | null
          postal_postal_code: string | null
          postal_postal_place: string | null
          postal_region_id: number | null
          postal_region_path: unknown | null
          primary_activity_category_id: number | null
          primary_activity_category_path: unknown | null
          search: unknown | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: unknown | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: unknown | null
          stat_ident: string | null
          tax_ident: string | null
          turnover: number | null
          unit_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Relationships: [
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
            referencedRelation: "activity_category"
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
            columns: ["primary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used"
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
            columns: ["secondary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_by_tag_id_fkey"
            columns: ["by_tag_id"]
            isOneToOne: false
            referencedRelation: "tag"
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
            referencedRelation: "timeline_enterprise"
            referencedColumns: ["enterprise_id"]
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
            referencedRelation: "country_used"
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
            referencedRelation: "country_used"
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
            referencedRelation: "region_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["postal_region_id"]
            isOneToOne: false
            referencedRelation: "region_used"
            referencedColumns: ["id"]
          },
        ]
      }
      timeline_legal_unit: {
        Row: {
          activity_category_paths: unknown[] | null
          birth_date: string | null
          by_tag_id: number | null
          by_tag_id_unique_ident: string | null
          death_date: string | null
          employees: number | null
          enterprise_id: number | null
          establishment_ids: number[] | null
          external_ident: string | null
          external_ident_type: string | null
          invalid_codes: Json | null
          legal_form_code: string | null
          legal_form_id: number | null
          legal_form_name: string | null
          legal_unit_id: number | null
          name: string | null
          physical_address_part1: string | null
          physical_address_part2: string | null
          physical_address_part3: string | null
          physical_country_id: number | null
          physical_country_iso_2: string | null
          physical_postal_code: string | null
          physical_postal_place: string | null
          physical_region_id: number | null
          physical_region_path: unknown | null
          postal_address_part1: string | null
          postal_address_part2: string | null
          postal_address_part3: string | null
          postal_country_id: number | null
          postal_country_iso_2: string | null
          postal_postal_code: string | null
          postal_postal_place: string | null
          postal_region_id: number | null
          postal_region_path: unknown | null
          primary_activity_category_id: number | null
          primary_activity_category_path: unknown | null
          search: unknown | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: unknown | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: unknown | null
          stat_ident: string | null
          tax_ident: string | null
          turnover: number | null
          unit_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_after: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Relationships: [
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
            referencedRelation: "activity_category"
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
            columns: ["primary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used"
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
            columns: ["secondary_activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_by_tag_id_fkey"
            columns: ["by_tag_id"]
            isOneToOne: false
            referencedRelation: "tag"
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
            referencedRelation: "timeline_enterprise"
            referencedColumns: ["enterprise_id"]
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
            referencedRelation: "country_used"
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
            referencedRelation: "country_used"
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
            referencedRelation: "region_used"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["postal_region_id"]
            isOneToOne: false
            referencedRelation: "region_used"
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
      timesegments: {
        Row: {
          unit_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_after: string | null
          valid_to: string | null
        }
        Relationships: []
      }
      unit_size_custom: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      unit_size_system: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        }
        Insert: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Update: {
          active?: boolean | null
          code?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      _ltree_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      _ltree_gist_options: {
        Args: {
          "": unknown
        }
        Returns: undefined
      }
      activity_category_hierarchy: {
        Args: {
          activity_category_id: number
        }
        Returns: Json
      }
      activity_category_standard_hierarchy: {
        Args: {
          standard_id: number
        }
        Returns: Json
      }
      activity_hierarchy: {
        Args: {
          parent_establishment_id?: number
          parent_legal_unit_id?: number
          valid_on?: string
        }
        Returns: Json
      }
      build_tsquery_from_parts: {
        Args: {
          query_parts: Database["public"]["CompositeTypes"]["tsquery_part"][]
        }
        Returns: unknown
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
      country_hierarchy: {
        Args: {
          country_id: number
        }
        Returns: Json
      }
      enterprise_hierarchy: {
        Args: {
          enterprise_id: number
          valid_on?: string
        }
        Returns: Json
      }
      establishment_hierarchy: {
        Args: {
          parent_legal_unit_id?: number
          parent_enterprise_id?: number
          valid_on?: string
        }
        Returns: Json
      }
      gbt_bit_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_bool_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_bool_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_bpchar_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_bytea_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_cash_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_cash_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_date_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_date_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_decompress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_enum_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_enum_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_float4_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_float4_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_float8_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_float8_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_inet_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_int2_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_int2_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_int4_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_int4_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_int8_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_int8_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_intv_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_intv_decompress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_intv_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_macad_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_macad_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_macad8_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_macad8_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_numeric_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_oid_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_oid_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_text_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_time_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_time_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_timetz_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_ts_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_ts_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_tstz_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_uuid_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_uuid_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_var_decompress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbt_var_fetch: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbtreekey_var_in: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbtreekey_var_out: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbtreekey16_in: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbtreekey16_out: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbtreekey2_in: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbtreekey2_out: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbtreekey32_in: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbtreekey32_out: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbtreekey4_in: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbtreekey4_out: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbtreekey8_in: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      gbtreekey8_out: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      generate_mermaid_er_diagram: {
        Args: Record<PropertyKey, never>
        Returns: string
      }
      jsonb_ast_to_tsquery: {
        Args: {
          ast: Json
        }
        Returns: unknown
      }
      jsonb_concat: {
        Args: {
          state: Json
          value: Json
        }
        Returns: Json
      }
      lca: {
        Args: {
          "": unknown[]
        }
        Returns: unknown
      }
      legal_form_hierarchy: {
        Args: {
          legal_form_id: number
        }
        Returns: Json
      }
      legal_unit_hierarchy: {
        Args: {
          parent_enterprise_id: number
          valid_on?: string
        }
        Returns: Json
      }
      location_hierarchy: {
        Args: {
          parent_establishment_id?: number
          parent_legal_unit_id?: number
          valid_on?: string
        }
        Returns: Json
      }
      lquery_in: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      lquery_out: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      lquery_recv: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      lquery_send: {
        Args: {
          "": unknown
        }
        Returns: string
      }
      ltree_compress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      ltree_decompress: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      ltree_gist_in: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      ltree_gist_options: {
        Args: {
          "": unknown
        }
        Returns: undefined
      }
      ltree_gist_out: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      ltree_in: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      ltree_out: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      ltree_recv: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      ltree_send: {
        Args: {
          "": unknown
        }
        Returns: string
      }
      ltree2text: {
        Args: {
          "": unknown
        }
        Returns: string
      }
      ltxtq_in: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      ltxtq_out: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      ltxtq_recv: {
        Args: {
          "": unknown
        }
        Returns: unknown
      }
      ltxtq_send: {
        Args: {
          "": unknown
        }
        Returns: string
      }
      nlevel: {
        Args: {
          "": unknown
        }
        Returns: number
      }
      parse_query_to_parts: {
        Args: {
          query: string
        }
        Returns: Database["public"]["CompositeTypes"]["tsquery_part"][]
      }
      pop_jsonb: {
        Args: {
          var_stack: Json[]
        }
        Returns: Json
      }
      pop_text: {
        Args: {
          var_stack: string[]
        }
        Returns: string
      }
      push: {
        Args: {
          var: unknown
          var_stack: unknown
        }
        Returns: unknown
      }
      push_jsonb: {
        Args: {
          var: Json
          var_stack: Json[]
        }
        Returns: Json[]
      }
      push_text: {
        Args: {
          var: string
          var_stack: string[]
        }
        Returns: string[]
      }
      query_to_jsonb_ast: {
        Args: {
          query: string
        }
        Returns: Json
      }
      recursive_build_tsquery: {
        Args: {
          node: Json
          result: string
        }
        Returns: string
      }
      region_hierarchy: {
        Args: {
          region_id: number
        }
        Returns: Json
      }
      reset_all_data: {
        Args: {
          confirmed: boolean
        }
        Returns: Json
      }
      sector_hierarchy: {
        Args: {
          sector_id: number
        }
        Returns: Json
      }
      set_primary_establishment_for_legal_unit: {
        Args: {
          establishment_id: number
          valid_from?: string
          valid_to?: string
        }
        Returns: Json
      }
      set_primary_legal_unit_for_enterprise: {
        Args: {
          legal_unit_id: number
          valid_from?: string
          valid_to?: string
        }
        Returns: Json
      }
      stat_for_unit_hierarchy: {
        Args: {
          parent_establishment_id: number
          valid_on?: string
        }
        Returns: Json
      }
      statistical_history_drilldown: {
        Args: {
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          type?: Database["public"]["Enums"]["statistical_history_type"]
          year?: number
          region_path?: unknown
          activity_category_path?: unknown
          sector_path?: unknown
          legal_form_id?: number
          country_id?: number
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
      statistical_unit_facet_drilldown: {
        Args: {
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          region_path?: unknown
          activity_category_path?: unknown
          sector_path?: unknown
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
          valid_on?: string
        }
        Returns: Json
      }
      statistical_unit_refresh_now: {
        Args: Record<PropertyKey, never>
        Returns: {
          view_name: string
          refresh_time_ms: number
        }[]
      }
      statistical_unit_refreshed_at: {
        Args: Record<PropertyKey, never>
        Returns: {
          view_name: string
          modified_at: string
        }[]
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
      text2ltree: {
        Args: {
          "": string
        }
        Returns: unknown
      }
      websearch_to_wildcard_tsquery: {
        Args: {
          query: string
        }
        Returns: unknown
      }
    }
    Enums: {
      activity_type: "primary" | "secondary" | "ancilliary"
      location_type: "physical" | "postal"
      op_type: "AND" | "OR" | "NOT" | "PHRASE" | "WORD"
      period_type: "relative_period" | "tag"
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
      statbus_role_type:
        | "super_user"
        | "regular_user"
        | "restricted_user"
        | "external_user"
      statistical_history_type: "year" | "year-month"
      statistical_unit_type:
        | "establishment"
        | "legal_unit"
        | "enterprise"
        | "enterprise_group"
      tag_type: "custom" | "system"
    }
    CompositeTypes: {
      tsquery_part: {
        position: number | null
        op: Database["public"]["Enums"]["op_type"] | null
        args: string[] | null
      }
    }
  }
}

type PublicSchema = Database[Extract<keyof Database, "public">]

export type Tables<
  PublicTableNameOrOptions extends
    | keyof (PublicSchema["Tables"] & PublicSchema["Views"])
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
        Database[PublicTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
      Database[PublicTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : PublicTableNameOrOptions extends keyof (PublicSchema["Tables"] &
        PublicSchema["Views"])
    ? (PublicSchema["Tables"] &
        PublicSchema["Views"])[PublicTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  PublicTableNameOrOptions extends
    | keyof PublicSchema["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : PublicTableNameOrOptions extends keyof PublicSchema["Tables"]
    ? PublicSchema["Tables"][PublicTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  PublicTableNameOrOptions extends
    | keyof PublicSchema["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : PublicTableNameOrOptions extends keyof PublicSchema["Tables"]
    ? PublicSchema["Tables"][PublicTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  PublicEnumNameOrOptions extends
    | keyof PublicSchema["Enums"]
    | { schema: keyof Database },
  EnumName extends PublicEnumNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = PublicEnumNameOrOptions extends { schema: keyof Database }
  ? Database[PublicEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : PublicEnumNameOrOptions extends keyof PublicSchema["Enums"]
    ? PublicSchema["Enums"][PublicEnumNameOrOptions]
    : never

