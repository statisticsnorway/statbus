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
          valid_from: string
          valid_range: string
          valid_to: string | null
          valid_until: string | null
        },
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
          valid_from: string
          valid_range: string
          valid_to?: string | null
          valid_until?: string | null
        },
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
          valid_from?: string
          valid_range?: string
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
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
            foreignKeyName: "activity_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "activity_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit"
            referencedColumns: ["id", "valid_range"]
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
            foreignKeyName: "activity_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["establishment_id"]
          },
          {
            foreignKeyName: "activity_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["legal_unit_id"]
          },
          {
            foreignKeyName: "activity_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      activity_category: {
        Row: {
          code: string
          created_at: string
          custom: boolean
          description: string | null
          enabled: boolean
          id: number
          label: string
          level: number | null
          name: string
          parent_id: number | null
          path: string
          standard_id: number
          updated_at: string
        },
        Insert: {
          code: string
          created_at?: string
          custom: boolean
          description?: string | null
          enabled: boolean
          id?: never
          label: string
          level?: number | null
          name: string
          parent_id?: number | null
          path: string
          standard_id: number
          updated_at?: string
        },
        Update: {
          code?: string
          created_at?: string
          custom?: boolean
          description?: string | null
          enabled?: boolean
          id?: never
          label?: string
          level?: number | null
          name?: string
          parent_id?: number | null
          path?: string
          standard_id?: number
          updated_at?: string
        },
        Relationships: [
          {
            foreignKeyName: "activity_category_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_category_standard_id_fkey"
            columns: ["standard_id"]
            isOneToOne: false
            referencedRelation: "activity_category_standard"
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
            foreignKeyName: "activity_category_standard_id_fkey"
            columns: ["standard_id"]
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
            referencedRelation: "activity_category_used_def"
            referencedColumns: ["id"]
          }
        ]
      },
      activity_category_access: {
        Row: {
          activity_category_id: number
          id: number
          user_id: number
        },
        Insert: {
          activity_category_id: number
          id?: never
          user_id: number
        },
        Update: {
          activity_category_id?: number
          id?: never
          user_id?: number
        },
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
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      activity_category_standard: {
        Row: {
          code: string
          code_pattern: Database["public"]["Enums"]["activity_category_code_behaviour"]
          description: string
          enabled: boolean
          id: number
          name: string
        },
        Insert: {
          code: string
          code_pattern: Database["public"]["Enums"]["activity_category_code_behaviour"]
          description: string
          enabled?: boolean
          id?: never
          name: string
        },
        Update: {
          code?: string
          code_pattern?: Database["public"]["Enums"]["activity_category_code_behaviour"]
          description?: string
          enabled?: boolean
          id?: never
          name?: string
        },
        Relationships: []
      },
      activity_category_used: {
        Row: {
          code: string | null
          description: string | null
          id: number | null
          label: string | null
          name: string | null
          parent_path: string | null
          path: string | null
          standard_code: string | null
        },
        Insert: {
          code?: string | null
          description?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_path?: string | null
          path?: string | null
          standard_code?: string | null
        },
        Update: {
          code?: string | null
          description?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_path?: string | null
          path?: string | null
          standard_code?: string | null
        },
        Relationships: []
      },
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
          valid_from: string
          valid_range: string
          valid_to: string | null
          valid_until: string | null
          web_address: string | null
        },
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
          valid_from: string
          valid_range: string
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
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
          valid_from?: string
          valid_range?: string
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "contact_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contact_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "contact_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit"
            referencedColumns: ["id", "valid_range"]
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
            foreignKeyName: "contact_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contact_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contact_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["establishment_id"]
          },
          {
            foreignKeyName: "contact_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["legal_unit_id"]
          },
          {
            foreignKeyName: "contact_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      country: {
        Row: {
          created_at: string
          custom: boolean
          enabled: boolean
          id: number
          iso_2: string
          iso_3: string
          iso_num: string
          name: string
          updated_at: string
        },
        Insert: {
          created_at?: string
          custom: boolean
          enabled: boolean
          id?: never
          iso_2: string
          iso_3: string
          iso_num: string
          name: string
          updated_at?: string
        },
        Update: {
          created_at?: string
          custom?: boolean
          enabled?: boolean
          id?: never
          iso_2?: string
          iso_3?: string
          iso_num?: string
          name?: string
          updated_at?: string
        },
        Relationships: []
      },
      country_used: {
        Row: {
          id: number | null
          iso_2: string | null
          name: string | null
        },
        Insert: {
          id?: number | null
          iso_2?: string | null
          name?: string | null
        },
        Update: {
          id?: number | null
          iso_2?: string | null
          name?: string | null
        },
        Relationships: []
      },
      data_source: {
        Row: {
          code: string
          created_at: string
          custom: boolean
          enabled: boolean
          id: number
          name: string
          updated_at: string
        },
        Insert: {
          code: string
          created_at?: string
          custom: boolean
          enabled: boolean
          id?: never
          name: string
          updated_at?: string
        },
        Update: {
          code?: string
          created_at?: string
          custom?: boolean
          enabled?: boolean
          id?: never
          name?: string
          updated_at?: string
        },
        Relationships: []
      },
      data_source_used: {
        Row: {
          code: string | null
          id: number | null
          name: string | null
        },
        Insert: {
          code?: string | null
          id?: number | null
          name?: string | null
        },
        Update: {
          code?: string | null
          id?: number | null
          name?: string | null
        },
        Relationships: []
      },
      enterprise: {
        Row: {
          edit_at: string
          edit_by_user_id: number
          edit_comment: string | null
          enabled: boolean
          id: number
          short_name: string | null
        },
        Insert: {
          edit_at?: string
          edit_by_user_id: number
          edit_comment?: string | null
          enabled?: boolean
          id?: never
          short_name?: string | null
        },
        Update: {
          edit_at?: string
          edit_by_user_id?: number
          edit_comment?: string | null
          enabled?: boolean
          id?: never
          short_name?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "enterprise_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      enterprise_group: {
        Row: {
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
          valid_from: string
          valid_range: string
          valid_to: string | null
          valid_until: string | null
        },
        Insert: {
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
          valid_from: string
          valid_range: string
          valid_to?: string | null
          valid_until?: string | null
        },
        Update: {
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
          valid_from?: string
          valid_range?: string
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "enterprise_group_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
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
            foreignKeyName: "enterprise_group_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation"
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
            foreignKeyName: "enterprise_group_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size"
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
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["unit_size_id"]
          },
          {
            foreignKeyName: "enterprise_group_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["unit_size_id"]
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
          {
            foreignKeyName: "enterprise_group_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      enterprise_group_role: {
        Row: {
          code: string
          created_at: string
          custom: boolean
          enabled: boolean
          id: number
          name: string
          updated_at: string
        },
        Insert: {
          code: string
          created_at?: string
          custom: boolean
          enabled: boolean
          id?: never
          name: string
          updated_at?: string
        },
        Update: {
          code?: string
          created_at?: string
          custom?: boolean
          enabled?: boolean
          id?: never
          name?: string
          updated_at?: string
        },
        Relationships: []
      },
      enterprise_group_type: {
        Row: {
          code: string
          created_at: string
          custom: boolean
          enabled: boolean
          id: number
          name: string
          updated_at: string
        },
        Insert: {
          code: string
          created_at?: string
          custom: boolean
          enabled: boolean
          id?: never
          name: string
          updated_at?: string
        },
        Update: {
          code?: string
          created_at?: string
          custom?: boolean
          enabled?: boolean
          id?: never
          name?: string
          updated_at?: string
        },
        Relationships: []
      },
      establishment: {
        Row: {
          birth_date: string | null
          data_source_id: number | null
          death_date: string | null
          edit_at: string
          edit_by_user_id: number
          edit_comment: string | null
          enterprise_id: number | null
          free_econ_zone: boolean | null
          id: number
          image_id: number | null
          legal_unit_id: number | null
          name: string
          primary_for_enterprise: boolean | null
          primary_for_legal_unit: boolean | null
          sector_id: number | null
          short_name: string | null
          status_id: number
          unit_size_id: number | null
          valid_from: string
          valid_range: string
          valid_to: string | null
          valid_until: string | null
        },
        Insert: {
          birth_date?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_at?: string
          edit_by_user_id: number
          edit_comment?: string | null
          enterprise_id?: number | null
          free_econ_zone?: boolean | null
          id?: number
          image_id?: number | null
          legal_unit_id?: number | null
          name: string
          primary_for_enterprise?: boolean | null
          primary_for_legal_unit?: boolean | null
          sector_id?: number | null
          short_name?: string | null
          status_id: number
          unit_size_id?: number | null
          valid_from: string
          valid_range: string
          valid_to?: string | null
          valid_until?: string | null
        },
        Update: {
          birth_date?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_at?: string
          edit_by_user_id?: number
          edit_comment?: string | null
          enterprise_id?: number | null
          free_econ_zone?: boolean | null
          id?: number
          image_id?: number | null
          legal_unit_id?: number | null
          name?: string
          primary_for_enterprise?: boolean | null
          primary_for_legal_unit?: boolean | null
          sector_id?: number | null
          short_name?: string | null
          status_id?: number
          unit_size_id?: number | null
          valid_from?: string
          valid_range?: string
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "establishment_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
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
            foreignKeyName: "establishment_image_id_fkey"
            columns: ["image_id"]
            isOneToOne: false
            referencedRelation: "image"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector"
            referencedColumns: ["id"]
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
            foreignKeyName: "establishment_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit__for_portion_of_valid"
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
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "establishment_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["status_id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["unit_size_id"]
          },
          {
            foreignKeyName: "establishment_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["legal_unit_id"]
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
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["status_id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["unit_size_id"]
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
            foreignKeyName: "establishment_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      external_ident: {
        Row: {
          edit_at: string
          edit_by_user_id: number
          edit_comment: string | null
          enterprise_group_id: number | null
          enterprise_id: number | null
          establishment_id: number | null
          id: number
          ident: string | null
          idents: string | null
          labels: string | null
          legal_unit_id: number | null
          shape: Database["public"]["Enums"]["external_ident_shape"]
          type_id: number
        },
        Insert: {
          edit_at?: string
          edit_by_user_id: number
          edit_comment?: string | null
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: number
          ident?: string | null
          idents?: string | null
          labels?: string | null
          legal_unit_id?: number | null
          shape: Database["public"]["Enums"]["external_ident_shape"]
          type_id: number
        },
        Update: {
          edit_at?: string
          edit_by_user_id?: number
          edit_comment?: string | null
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: number
          ident?: string | null
          idents?: string | null
          labels?: string | null
          legal_unit_id?: number | null
          shape?: Database["public"]["Enums"]["external_ident_shape"]
          type_id?: number
        },
        Relationships: [
          {
            foreignKeyName: "external_ident_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "enterprise"
            referencedColumns: ["id"]
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
          {
            foreignKeyName: "external_ident_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise_def"
            referencedColumns: ["enterprise_id"]
          },
          {
            foreignKeyName: "external_ident_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      external_ident_type: {
        Row: {
          code: string
          description: string | null
          enabled: boolean
          id: number
          labels: string | null
          name: string | null
          priority: number | null
          shape: Database["public"]["Enums"]["external_ident_shape"]
        },
        Insert: {
          code: string
          description?: string | null
          enabled?: boolean
          id?: never
          labels?: string | null
          name?: string | null
          priority?: number | null
          shape?: Database["public"]["Enums"]["external_ident_shape"]
        },
        Update: {
          code?: string
          description?: string | null
          enabled?: boolean
          id?: never
          labels?: string | null
          name?: string | null
          priority?: number | null
          shape?: Database["public"]["Enums"]["external_ident_shape"]
        },
        Relationships: []
      },
      foreign_participation: {
        Row: {
          code: string
          created_at: string
          custom: boolean
          enabled: boolean
          id: number
          name: string
          updated_at: string
        },
        Insert: {
          code: string
          created_at?: string
          custom: boolean
          enabled: boolean
          id?: never
          name: string
          updated_at?: string
        },
        Update: {
          code?: string
          created_at?: string
          custom?: boolean
          enabled?: boolean
          id?: never
          name?: string
          updated_at?: string
        },
        Relationships: []
      },
      image: {
        Row: {
          data: string
          id: number
          type: string
          uploaded_at: string
          uploaded_by_user_id: number | null
        },
        Insert: {
          data: string
          id?: never
          type?: string
          uploaded_at?: string
          uploaded_by_user_id?: number | null
        },
        Update: {
          data?: string
          id?: never
          type?: string
          uploaded_at?: string
          uploaded_by_user_id?: number | null
        },
        Relationships: [
          {
            foreignKeyName: "image_uploaded_by_user_id_fkey"
            columns: ["uploaded_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      import_data_column: {
        Row: {
          column_name: string
          column_type: string
          created_at: string
          default_value: string | null
          id: number
          is_nullable: boolean
          is_uniquely_identifying: boolean
          priority: number | null
          purpose: Database["public"]["Enums"]["import_data_column_purpose"]
          step_id: number
          updated_at: string
        },
        Insert: {
          column_name: string
          column_type: string
          created_at?: string
          default_value?: string | null
          id?: never
          is_nullable?: boolean
          is_uniquely_identifying?: boolean
          priority?: number | null
          purpose: Database["public"]["Enums"]["import_data_column_purpose"]
          step_id: number
          updated_at?: string
        },
        Update: {
          column_name?: string
          column_type?: string
          created_at?: string
          default_value?: string | null
          id?: never
          is_nullable?: boolean
          is_uniquely_identifying?: boolean
          priority?: number | null
          purpose?: Database["public"]["Enums"]["import_data_column_purpose"]
          step_id?: number
          updated_at?: string
        },
        Relationships: [
          {
            foreignKeyName: "import_data_column_step_id_fkey"
            columns: ["step_id"]
            isOneToOne: false
            referencedRelation: "import_step"
            referencedColumns: ["id"]
          }
        ]
      },
      import_definition: {
        Row: {
          created_at: string
          custom: boolean
          data_source_id: number | null
          default_retention_period: string
          enabled: boolean
          id: number
          import_as_null: string[]
          mode: Database["public"]["Enums"]["import_mode"]
          name: string
          note: string | null
          slug: string
          strategy: Database["public"]["Enums"]["import_strategy"]
          updated_at: string
          user_id: number | null
          valid: boolean
          valid_time_from: Database["public"]["Enums"]["import_valid_time_from"]
          validation_error: string | null
        },
        Insert: {
          created_at?: string
          custom?: boolean
          data_source_id?: number | null
          default_retention_period?: string
          enabled?: boolean
          id?: never
          import_as_null?: string[]
          mode: Database["public"]["Enums"]["import_mode"]
          name: string
          note?: string | null
          slug: string
          strategy?: Database["public"]["Enums"]["import_strategy"]
          updated_at?: string
          user_id?: number | null
          valid?: boolean
          valid_time_from: Database["public"]["Enums"]["import_valid_time_from"]
          validation_error?: string | null
        },
        Update: {
          created_at?: string
          custom?: boolean
          data_source_id?: number | null
          default_retention_period?: string
          enabled?: boolean
          id?: never
          import_as_null?: string[]
          mode?: Database["public"]["Enums"]["import_mode"]
          name?: string
          note?: string | null
          slug?: string
          strategy?: Database["public"]["Enums"]["import_strategy"]
          updated_at?: string
          user_id?: number | null
          valid?: boolean
          valid_time_from?: Database["public"]["Enums"]["import_valid_time_from"]
          validation_error?: string | null
        },
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
            foreignKeyName: "import_definition_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      import_definition_step: {
        Row: {
          definition_id: number
          step_id: number
        },
        Insert: {
          definition_id: number
          step_id: number
        },
        Update: {
          definition_id?: number
          step_id?: number
        },
        Relationships: [
          {
            foreignKeyName: "import_definition_step_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "import_definition"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "import_definition_step_step_id_fkey"
            columns: ["step_id"]
            isOneToOne: false
            referencedRelation: "import_step"
            referencedColumns: ["id"]
          }
        ]
      },
      import_job: {
        Row: {
          analysis_batch_size: number
          analysis_completed_pct: number | null
          analysis_rows_per_sec: number | null
          analysis_start_at: string | null
          analysis_stop_at: string | null
          changes_approved_at: string | null
          changes_rejected_at: string | null
          completed_analysis_steps_weighted: number | null
          created_at: string
          current_step_code: string | null
          current_step_priority: number | null
          data_table_name: string
          default_data_source_code: string | null
          default_valid_from: string | null
          default_valid_to: string | null
          definition_id: number
          definition_snapshot: Json | null
          description: string | null
          edit_comment: string | null
          error: string | null
          expires_at: string
          id: number
          import_completed_pct: number | null
          import_rows_per_sec: number | null
          imported_rows: number | null
          last_progress_update: string | null
          max_analysis_priority: number | null
          note: string | null
          preparing_data_at: string | null
          priority: number | null
          processing_batch_size: number
          processing_start_at: string | null
          processing_stop_at: string | null
          review: boolean
          slug: string
          state: Database["public"]["Enums"]["import_job_state"]
          time_context_ident: string | null
          total_analysis_steps_weighted: number | null
          total_rows: number | null
          updated_at: string
          upload_table_name: string
          user_id: number | null
        },
        Insert: {
          analysis_batch_size?: number
          analysis_completed_pct?: number | null
          analysis_rows_per_sec?: number | null
          analysis_start_at?: string | null
          analysis_stop_at?: string | null
          changes_approved_at?: string | null
          changes_rejected_at?: string | null
          completed_analysis_steps_weighted?: number | null
          created_at?: string
          current_step_code?: string | null
          current_step_priority?: number | null
          data_table_name: string
          default_data_source_code?: string | null
          default_valid_from?: string | null
          default_valid_to?: string | null
          definition_id: number
          definition_snapshot?: Json | null
          description?: string | null
          edit_comment?: string | null
          error?: string | null
          expires_at: string
          id?: never
          import_completed_pct?: number | null
          import_rows_per_sec?: number | null
          imported_rows?: number | null
          last_progress_update?: string | null
          max_analysis_priority?: number | null
          note?: string | null
          preparing_data_at?: string | null
          priority?: number | null
          processing_batch_size?: number
          processing_start_at?: string | null
          processing_stop_at?: string | null
          review?: boolean
          slug: string
          state?: Database["public"]["Enums"]["import_job_state"]
          time_context_ident?: string | null
          total_analysis_steps_weighted?: number | null
          total_rows?: number | null
          updated_at?: string
          upload_table_name: string
          user_id?: number | null
        },
        Update: {
          analysis_batch_size?: number
          analysis_completed_pct?: number | null
          analysis_rows_per_sec?: number | null
          analysis_start_at?: string | null
          analysis_stop_at?: string | null
          changes_approved_at?: string | null
          changes_rejected_at?: string | null
          completed_analysis_steps_weighted?: number | null
          created_at?: string
          current_step_code?: string | null
          current_step_priority?: number | null
          data_table_name?: string
          default_data_source_code?: string | null
          default_valid_from?: string | null
          default_valid_to?: string | null
          definition_id?: number
          definition_snapshot?: Json | null
          description?: string | null
          edit_comment?: string | null
          error?: string | null
          expires_at?: string
          id?: never
          import_completed_pct?: number | null
          import_rows_per_sec?: number | null
          imported_rows?: number | null
          last_progress_update?: string | null
          max_analysis_priority?: number | null
          note?: string | null
          preparing_data_at?: string | null
          priority?: number | null
          processing_batch_size?: number
          processing_start_at?: string | null
          processing_stop_at?: string | null
          review?: boolean
          slug?: string
          state?: Database["public"]["Enums"]["import_job_state"]
          time_context_ident?: string | null
          total_analysis_steps_weighted?: number | null
          total_rows?: number | null
          updated_at?: string
          upload_table_name?: string
          user_id?: number | null
        },
        Relationships: [
          {
            foreignKeyName: "import_job_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "import_definition"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "import_job_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      import_mapping: {
        Row: {
          created_at: string
          definition_id: number
          id: number
          is_ignored: boolean
          source_column_id: number | null
          source_expression: Database["public"]["Enums"]["import_source_expression"] | null
          source_value: string | null
          target_data_column_id: number | null
          target_data_column_purpose: Database["public"]["Enums"]["import_data_column_purpose"] | null
          updated_at: string
        },
        Insert: {
          created_at?: string
          definition_id: number
          id?: never
          is_ignored?: boolean
          source_column_id?: number | null
          source_expression?: Database["public"]["Enums"]["import_source_expression"] | null
          source_value?: string | null
          target_data_column_id?: number | null
          target_data_column_purpose?: Database["public"]["Enums"]["import_data_column_purpose"] | null
          updated_at?: string
        },
        Update: {
          created_at?: string
          definition_id?: number
          id?: never
          is_ignored?: boolean
          source_column_id?: number | null
          source_expression?: Database["public"]["Enums"]["import_source_expression"] | null
          source_value?: string | null
          target_data_column_id?: number | null
          target_data_column_purpose?: Database["public"]["Enums"]["import_data_column_purpose"] | null
          updated_at?: string
        },
        Relationships: [
          {
            foreignKeyName: "import_mapping_target_data_column_id_fkey"
            columns: ["target_data_column_id"]
            isOneToOne: false
            referencedRelation: "import_data_column"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "import_mapping_target_data_column_id_target_data_column_pu_fkey"
            columns: ["target_data_column_id", "target_data_column_purpose"]
            isOneToOne: false
            referencedRelation: "import_data_column"
            referencedColumns: ["id", "purpose"]
          },
          {
            foreignKeyName: "import_mapping_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "import_definition"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "import_mapping_source_column_id_fkey"
            columns: ["source_column_id"]
            isOneToOne: false
            referencedRelation: "import_source_column"
            referencedColumns: ["id"]
          }
        ]
      },
      import_source_column: {
        Row: {
          column_name: string
          created_at: string
          definition_id: number
          id: number
          priority: number
          updated_at: string
        },
        Insert: {
          column_name: string
          created_at?: string
          definition_id: number
          id?: never
          priority: number
          updated_at?: string
        },
        Update: {
          column_name?: string
          created_at?: string
          definition_id?: number
          id?: never
          priority?: number
          updated_at?: string
        },
        Relationships: [
          {
            foreignKeyName: "import_source_column_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "import_definition"
            referencedColumns: ["id"]
          }
        ]
      },
      import_step: {
        Row: {
          analyse_procedure: string | null
          code: string
          created_at: string
          id: number
          is_holistic: boolean
          name: string
          priority: number
          process_procedure: string | null
          updated_at: string
        },
        Insert: {
          analyse_procedure?: string | null
          code: string
          created_at?: string
          id?: never
          is_holistic: boolean
          name: string
          priority: number
          process_procedure?: string | null
          updated_at?: string
        },
        Update: {
          analyse_procedure?: string | null
          code?: string
          created_at?: string
          id?: never
          is_holistic?: boolean
          name?: string
          priority?: number
          process_procedure?: string | null
          updated_at?: string
        },
        Relationships: []
      },
      legal_form: {
        Row: {
          code: string
          created_at: string
          custom: boolean
          enabled: boolean
          id: number
          name: string
          updated_at: string
        },
        Insert: {
          code: string
          created_at?: string
          custom: boolean
          enabled: boolean
          id?: never
          name: string
          updated_at?: string
        },
        Update: {
          code?: string
          created_at?: string
          custom?: boolean
          enabled?: boolean
          id?: never
          name?: string
          updated_at?: string
        },
        Relationships: []
      },
      legal_form_used: {
        Row: {
          code: string | null
          id: number | null
          name: string | null
        },
        Insert: {
          code?: string | null
          id?: number | null
          name?: string | null
        },
        Update: {
          code?: string | null
          id?: number | null
          name?: string | null
        },
        Relationships: []
      },
      legal_unit: {
        Row: {
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
          image_id: number | null
          legal_form_id: number | null
          name: string
          primary_for_enterprise: boolean
          sector_id: number | null
          short_name: string | null
          status_id: number
          unit_size_id: number | null
          valid_from: string
          valid_range: string
          valid_to: string | null
          valid_until: string | null
        },
        Insert: {
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
          image_id?: number | null
          legal_form_id?: number | null
          name: string
          primary_for_enterprise: boolean
          sector_id?: number | null
          short_name?: string | null
          status_id: number
          unit_size_id?: number | null
          valid_from: string
          valid_range: string
          valid_to?: string | null
          valid_until?: string | null
        },
        Update: {
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
          image_id?: number | null
          legal_form_id?: number | null
          name?: string
          primary_for_enterprise?: boolean
          sector_id?: number | null
          short_name?: string | null
          status_id?: number
          unit_size_id?: number | null
          valid_from?: string
          valid_range?: string
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "legal_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
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
            foreignKeyName: "legal_unit_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_image_id_fkey"
            columns: ["image_id"]
            isOneToOne: false
            referencedRelation: "image"
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
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector"
            referencedColumns: ["id"]
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
            foreignKeyName: "legal_unit_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise_def"
            referencedColumns: ["enterprise_id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "legal_unit_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["status_id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["unit_size_id"]
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
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "legal_unit_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["status_id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["unit_size_id"]
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
            foreignKeyName: "legal_unit_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
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
          valid_from: string
          valid_range: string
          valid_to: string | null
          valid_until: string | null
        },
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
          valid_from: string
          valid_range: string
          valid_to?: string | null
          valid_until?: string | null
        },
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
          valid_from?: string
          valid_range?: string
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country"
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
            foreignKeyName: "location_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "location_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "region"
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
            foreignKeyName: "location_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "region_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["establishment_id"]
          },
          {
            foreignKeyName: "location_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["legal_unit_id"]
          },
          {
            foreignKeyName: "location_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
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
        },
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
        },
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
        },
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
          }
        ]
      },
      person_for_unit: {
        Row: {
          data_source_id: number | null
          edit_at: string
          edit_by_user_id: number
          edit_comment: string | null
          establishment_id: number | null
          id: number
          legal_unit_id: number | null
          person_id: number
          person_role_id: number | null
          valid_from: string
          valid_range: string
          valid_to: string | null
          valid_until: string | null
        },
        Insert: {
          data_source_id?: number | null
          edit_at?: string
          edit_by_user_id: number
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number
          legal_unit_id?: number | null
          person_id: number
          person_role_id?: number | null
          valid_from: string
          valid_range: string
          valid_to?: string | null
          valid_until?: string | null
        },
        Update: {
          data_source_id?: number | null
          edit_at?: string
          edit_by_user_id?: number
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number
          legal_unit_id?: number | null
          person_id?: number
          person_role_id?: number | null
          valid_from?: string
          valid_range?: string
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "person_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_for_unit_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "person_for_unit_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit"
            referencedColumns: ["id", "valid_range"]
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
            foreignKeyName: "person_for_unit_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_for_unit_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit__for_portion_of_valid"
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
          {
            foreignKeyName: "person_for_unit_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["establishment_id"]
          },
          {
            foreignKeyName: "person_for_unit_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["legal_unit_id"]
          },
          {
            foreignKeyName: "person_for_unit_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      person_role: {
        Row: {
          code: string
          created_at: string
          custom: boolean
          enabled: boolean
          id: number
          name: string
          updated_at: string
        },
        Insert: {
          code: string
          created_at?: string
          custom: boolean
          enabled: boolean
          id?: never
          name: string
          updated_at?: string
        },
        Update: {
          code?: string
          created_at?: string
          custom?: boolean
          enabled?: boolean
          id?: never
          name?: string
          updated_at?: string
        },
        Relationships: []
      },
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
          path: string
        },
        Insert: {
          center_altitude?: number | null
          center_latitude?: number | null
          center_longitude?: number | null
          code?: string | null
          id?: number
          label: string
          level?: number | null
          name: string
          parent_id?: number | null
          path: string
        },
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
          path?: string
        },
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
          }
        ]
      },
      region_access: {
        Row: {
          id: number
          region_id: number
          user_id: number
        },
        Insert: {
          id?: never
          region_id: number
          user_id: number
        },
        Update: {
          id?: never
          region_id?: number
          user_id?: number
        },
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
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      region_used: {
        Row: {
          code: string | null
          id: number | null
          label: string | null
          level: number | null
          name: string | null
          path: string | null
        },
        Insert: {
          code?: string | null
          id?: number | null
          label?: string | null
          level?: number | null
          name?: string | null
          path?: string | null
        },
        Update: {
          code?: string | null
          id?: number | null
          label?: string | null
          level?: number | null
          name?: string | null
          path?: string | null
        },
        Relationships: []
      },
      relative_period: {
        Row: {
          code: Database["public"]["Enums"]["relative_period_code"]
          enabled: boolean
          id: number
          name_when_input: string | null
          name_when_query: string | null
          scope: Database["public"]["Enums"]["relative_period_scope"]
        },
        Insert: {
          code: Database["public"]["Enums"]["relative_period_code"]
          enabled?: boolean
          id?: never
          name_when_input?: string | null
          name_when_query?: string | null
          scope: Database["public"]["Enums"]["relative_period_scope"]
        },
        Update: {
          code?: Database["public"]["Enums"]["relative_period_code"]
          enabled?: boolean
          id?: never
          name_when_input?: string | null
          name_when_query?: string | null
          scope?: Database["public"]["Enums"]["relative_period_scope"]
        },
        Relationships: []
      },
      reorg_type: {
        Row: {
          code: string
          created_at: string
          custom: boolean
          description: string
          enabled: boolean
          id: number
          name: string
          updated_at: string
        },
        Insert: {
          code: string
          created_at?: string
          custom: boolean
          description: string
          enabled: boolean
          id?: never
          name: string
          updated_at?: string
        },
        Update: {
          code?: string
          created_at?: string
          custom?: boolean
          description?: string
          enabled?: boolean
          id?: never
          name?: string
          updated_at?: string
        },
        Relationships: []
      },
      sector: {
        Row: {
          code: string | null
          created_at: string
          custom: boolean
          description: string | null
          enabled: boolean
          id: number
          label: string
          name: string
          parent_id: number | null
          path: string
          updated_at: string
        },
        Insert: {
          code?: string | null
          created_at?: string
          custom: boolean
          description?: string | null
          enabled: boolean
          id?: never
          label: string
          name: string
          parent_id?: number | null
          path: string
          updated_at?: string
        },
        Update: {
          code?: string | null
          created_at?: string
          custom?: boolean
          description?: string | null
          enabled?: boolean
          id?: never
          label?: string
          name?: string
          parent_id?: number | null
          path?: string
          updated_at?: string
        },
        Relationships: []
      },
      sector_used: {
        Row: {
          code: string | null
          id: number | null
          label: string | null
          name: string | null
          path: string | null
        },
        Insert: {
          code?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          path?: string | null
        },
        Update: {
          code?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          path?: string | null
        },
        Relationships: []
      },
      settings: {
        Row: {
          activity_category_standard_id: number
          analytics_partition_count: number
          country_id: number
          id: number
          only_one_setting: boolean | null
        },
        Insert: {
          activity_category_standard_id: number
          analytics_partition_count?: number
          country_id: number
          id?: never
          only_one_setting?: boolean | null
        },
        Update: {
          activity_category_standard_id?: number
          analytics_partition_count?: number
          country_id?: number
          id?: never
          only_one_setting?: boolean | null
        },
        Relationships: [
          {
            foreignKeyName: "settings_activity_category_standard_id_fkey"
            columns: ["activity_category_standard_id"]
            isOneToOne: false
            referencedRelation: "activity_category_standard"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "settings_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "settings_activity_category_standard_id_fkey"
            columns: ["activity_category_standard_id"]
            isOneToOne: false
            referencedRelation: "activity_category_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "settings_activity_category_standard_id_fkey"
            columns: ["activity_category_standard_id"]
            isOneToOne: false
            referencedRelation: "activity_category_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "settings_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "settings_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country_view"
            referencedColumns: ["id"]
          }
        ]
      },
      stat_definition: {
        Row: {
          code: string
          description: string | null
          enabled: boolean
          frequency: Database["public"]["Enums"]["stat_frequency"]
          id: number
          name: string
          priority: number | null
          type: Database["public"]["Enums"]["stat_type"]
        },
        Insert: {
          code: string
          description?: string | null
          enabled?: boolean
          frequency: Database["public"]["Enums"]["stat_frequency"]
          id?: number
          name: string
          priority?: number | null
          type: Database["public"]["Enums"]["stat_type"]
        },
        Update: {
          code?: string
          description?: string | null
          enabled?: boolean
          frequency?: Database["public"]["Enums"]["stat_frequency"]
          id?: number
          name?: string
          priority?: number | null
          type?: Database["public"]["Enums"]["stat_type"]
        },
        Relationships: []
      },
      stat_for_unit: {
        Row: {
          data_source_id: number | null
          edit_at: string
          edit_by_user_id: number
          edit_comment: string | null
          establishment_id: number | null
          id: number
          legal_unit_id: number | null
          stat: Json | null
          stat_definition_id: number
          valid_from: string
          valid_range: string
          valid_to: string | null
          valid_until: string | null
          value_bool: boolean | null
          value_float: number | null
          value_int: number | null
          value_string: string | null
        },
        Insert: {
          data_source_id?: number | null
          edit_at?: string
          edit_by_user_id: number
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number
          legal_unit_id?: number | null
          stat?: Json | null
          stat_definition_id: number
          valid_from: string
          valid_range: string
          valid_to?: string | null
          valid_until?: string | null
          value_bool?: boolean | null
          value_float?: number | null
          value_int?: number | null
          value_string?: string | null
        },
        Update: {
          data_source_id?: number | null
          edit_at?: string
          edit_by_user_id?: number
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number
          legal_unit_id?: number | null
          stat?: Json | null
          stat_definition_id?: number
          valid_from?: string
          valid_range?: string
          valid_to?: string | null
          valid_until?: string | null
          value_bool?: boolean | null
          value_float?: number | null
          value_int?: number | null
          value_string?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "stat_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "stat_for_unit_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "stat_for_unit_stat_definition_id_fkey"
            columns: ["stat_definition_id"]
            isOneToOne: false
            referencedRelation: "stat_definition"
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
            foreignKeyName: "stat_for_unit_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit__for_portion_of_valid"
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
          {
            foreignKeyName: "stat_for_unit_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["establishment_id"]
          },
          {
            foreignKeyName: "stat_for_unit_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["legal_unit_id"]
          },
          {
            foreignKeyName: "stat_for_unit_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      statistical_history: {
        Row: {
          births: number | null
          countable_added_count: number | null
          countable_change: number | null
          countable_count: number | null
          countable_removed_count: number | null
          deaths: number | null
          exists_added_count: number | null
          exists_change: number | null
          exists_count: number | null
          exists_removed_count: number | null
          legal_form_change_count: number | null
          month: number | null
          name_change_count: number | null
          partition_seq: number | null
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
        },
        Insert: {
          births?: number | null
          countable_added_count?: number | null
          countable_change?: number | null
          countable_count?: number | null
          countable_removed_count?: number | null
          deaths?: number | null
          exists_added_count?: number | null
          exists_change?: number | null
          exists_count?: number | null
          exists_removed_count?: number | null
          legal_form_change_count?: number | null
          month?: number | null
          name_change_count?: number | null
          partition_seq?: number | null
          physical_address_change_count?: number | null
          physical_country_change_count?: number | null
          physical_region_change_count?: number | null
          primary_activity_category_change_count?: number | null
          resolution?: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count?: number | null
          sector_change_count?: number | null
          stats_summary?: Json | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          year?: number | null
        },
        Update: {
          births?: number | null
          countable_added_count?: number | null
          countable_change?: number | null
          countable_count?: number | null
          countable_removed_count?: number | null
          deaths?: number | null
          exists_added_count?: number | null
          exists_change?: number | null
          exists_count?: number | null
          exists_removed_count?: number | null
          legal_form_change_count?: number | null
          month?: number | null
          name_change_count?: number | null
          partition_seq?: number | null
          physical_address_change_count?: number | null
          physical_country_change_count?: number | null
          physical_region_change_count?: number | null
          primary_activity_category_change_count?: number | null
          resolution?: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count?: number | null
          sector_change_count?: number | null
          stats_summary?: Json | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          year?: number | null
        },
        Relationships: []
      },
      statistical_history_facet: {
        Row: {
          births: number | null
          countable_added_count: number | null
          countable_change: number | null
          countable_count: number | null
          countable_removed_count: number | null
          deaths: number | null
          exists_added_count: number | null
          exists_change: number | null
          exists_count: number | null
          exists_removed_count: number | null
          legal_form_change_count: number | null
          legal_form_id: number | null
          month: number | null
          name_change_count: number | null
          physical_address_change_count: number | null
          physical_country_change_count: number | null
          physical_country_id: number | null
          physical_region_change_count: number | null
          physical_region_path: string | null
          primary_activity_category_change_count: number | null
          primary_activity_category_path: string | null
          resolution: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count: number | null
          secondary_activity_category_path: string | null
          sector_change_count: number | null
          sector_path: string | null
          stats_summary: Json | null
          status_change_count: number | null
          status_id: number | null
          unit_size_change_count: number | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          year: number | null
        },
        Insert: {
          births?: number | null
          countable_added_count?: number | null
          countable_change?: number | null
          countable_count?: number | null
          countable_removed_count?: number | null
          deaths?: number | null
          exists_added_count?: number | null
          exists_change?: number | null
          exists_count?: number | null
          exists_removed_count?: number | null
          legal_form_change_count?: number | null
          legal_form_id?: number | null
          month?: number | null
          name_change_count?: number | null
          physical_address_change_count?: number | null
          physical_country_change_count?: number | null
          physical_country_id?: number | null
          physical_region_change_count?: number | null
          physical_region_path?: string | null
          primary_activity_category_change_count?: number | null
          primary_activity_category_path?: string | null
          resolution?: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count?: number | null
          secondary_activity_category_path?: string | null
          sector_change_count?: number | null
          sector_path?: string | null
          stats_summary?: Json | null
          status_change_count?: number | null
          status_id?: number | null
          unit_size_change_count?: number | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          year?: number | null
        },
        Update: {
          births?: number | null
          countable_added_count?: number | null
          countable_change?: number | null
          countable_count?: number | null
          countable_removed_count?: number | null
          deaths?: number | null
          exists_added_count?: number | null
          exists_change?: number | null
          exists_count?: number | null
          exists_removed_count?: number | null
          legal_form_change_count?: number | null
          legal_form_id?: number | null
          month?: number | null
          name_change_count?: number | null
          physical_address_change_count?: number | null
          physical_country_change_count?: number | null
          physical_country_id?: number | null
          physical_region_change_count?: number | null
          physical_region_path?: string | null
          primary_activity_category_change_count?: number | null
          primary_activity_category_path?: string | null
          resolution?: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count?: number | null
          secondary_activity_category_path?: string | null
          sector_change_count?: number | null
          sector_path?: string | null
          stats_summary?: Json | null
          status_change_count?: number | null
          status_id?: number | null
          unit_size_change_count?: number | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          year?: number | null
        },
        Relationships: []
      },
      statistical_history_facet_partitions: {
        Row: {
          births: number | null
          countable_added_count: number | null
          countable_change: number | null
          countable_count: number | null
          countable_removed_count: number | null
          deaths: number | null
          exists_added_count: number | null
          exists_change: number | null
          exists_count: number | null
          exists_removed_count: number | null
          legal_form_change_count: number | null
          legal_form_id: number | null
          month: number | null
          name_change_count: number | null
          partition_seq: number
          physical_address_change_count: number | null
          physical_country_change_count: number | null
          physical_country_id: number | null
          physical_region_change_count: number | null
          physical_region_path: string | null
          primary_activity_category_change_count: number | null
          primary_activity_category_path: string | null
          resolution: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count: number | null
          secondary_activity_category_path: string | null
          sector_change_count: number | null
          sector_path: string | null
          stats_summary: Json | null
          status_change_count: number | null
          status_id: number | null
          unit_size_change_count: number | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          year: number | null
        },
        Insert: {
          births?: number | null
          countable_added_count?: number | null
          countable_change?: number | null
          countable_count?: number | null
          countable_removed_count?: number | null
          deaths?: number | null
          exists_added_count?: number | null
          exists_change?: number | null
          exists_count?: number | null
          exists_removed_count?: number | null
          legal_form_change_count?: number | null
          legal_form_id?: number | null
          month?: number | null
          name_change_count?: number | null
          partition_seq: number
          physical_address_change_count?: number | null
          physical_country_change_count?: number | null
          physical_country_id?: number | null
          physical_region_change_count?: number | null
          physical_region_path?: string | null
          primary_activity_category_change_count?: number | null
          primary_activity_category_path?: string | null
          resolution?: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count?: number | null
          secondary_activity_category_path?: string | null
          sector_change_count?: number | null
          sector_path?: string | null
          stats_summary?: Json | null
          status_change_count?: number | null
          status_id?: number | null
          unit_size_change_count?: number | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          year?: number | null
        },
        Update: {
          births?: number | null
          countable_added_count?: number | null
          countable_change?: number | null
          countable_count?: number | null
          countable_removed_count?: number | null
          deaths?: number | null
          exists_added_count?: number | null
          exists_change?: number | null
          exists_count?: number | null
          exists_removed_count?: number | null
          legal_form_change_count?: number | null
          legal_form_id?: number | null
          month?: number | null
          name_change_count?: number | null
          partition_seq?: number
          physical_address_change_count?: number | null
          physical_country_change_count?: number | null
          physical_country_id?: number | null
          physical_region_change_count?: number | null
          physical_region_path?: string | null
          primary_activity_category_change_count?: number | null
          primary_activity_category_path?: string | null
          resolution?: Database["public"]["Enums"]["history_resolution"] | null
          secondary_activity_category_change_count?: number | null
          secondary_activity_category_path?: string | null
          sector_change_count?: number | null
          sector_path?: string | null
          stats_summary?: Json | null
          status_change_count?: number | null
          status_id?: number | null
          unit_size_change_count?: number | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          year?: number | null
        },
        Relationships: []
      },
      statistical_unit: {
        Row: {
          activity_category_paths: string[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          domestic: boolean | null
          email_address: string | null
          excluded_enterprise_ids: number[] | null
          excluded_establishment_ids: number[] | null
          excluded_legal_unit_ids: number[] | null
          external_idents: Json | null
          fax_number: string | null
          has_legal_unit: boolean | null
          included_enterprise_count: number | null
          included_enterprise_ids: number[] | null
          included_establishment_count: number | null
          included_establishment_ids: number[] | null
          included_legal_unit_count: number | null
          included_legal_unit_ids: number[] | null
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
          physical_region_path: string | null
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
          postal_region_path: string | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: string | null
          related_enterprise_ids: number[] | null
          related_establishment_ids: number[] | null
          related_legal_unit_ids: number[] | null
          report_partition_seq: number | null
          search: string | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: string | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: string | null
          stats: Json | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          tag_paths: string[] | null
          unit_id: number
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          used_for_counting: boolean | null
          valid_from: string | null
          valid_range: string
          valid_to: string | null
          valid_until: string | null
          web_address: string | null
        },
        Insert: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          external_idents?: Json | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_count?: number | null
          included_enterprise_ids?: number[] | null
          included_establishment_count?: number | null
          included_establishment_ids?: number[] | null
          included_legal_unit_count?: number | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          report_partition_seq?: number | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          tag_paths?: string[] | null
          unit_id: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          used_for_counting?: boolean | null
          valid_from?: string | null
          valid_range: string
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
        Update: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          external_idents?: Json | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_count?: number | null
          included_enterprise_ids?: number[] | null
          included_establishment_count?: number | null
          included_establishment_ids?: number[] | null
          included_legal_unit_count?: number | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          report_partition_seq?: number | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          tag_paths?: string[] | null
          unit_id?: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          used_for_counting?: boolean | null
          valid_from?: string | null
          valid_range?: string
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
        Relationships: []
      },
      statistical_unit_facet: {
        Row: {
          count: number | null
          legal_form_id: number | null
          physical_country_id: number | null
          physical_region_path: string | null
          primary_activity_category_path: string | null
          sector_path: string | null
          stats_summary: Json | null
          status_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from: string | null
          valid_to: string | null
          valid_until: string | null
        },
        Insert: {
          count?: number | null
          legal_form_id?: number | null
          physical_country_id?: number | null
          physical_region_path?: string | null
          primary_activity_category_path?: string | null
          sector_path?: string | null
          stats_summary?: Json | null
          status_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Update: {
          count?: number | null
          legal_form_id?: number | null
          physical_country_id?: number | null
          physical_region_path?: string | null
          primary_activity_category_path?: string | null
          sector_path?: string | null
          stats_summary?: Json | null
          status_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: []
      },
      statistical_unit_facet_dirty_partitions: {
        Row: {
          partition_seq: number
        },
        Insert: {
          partition_seq: number
        },
        Update: {
          partition_seq?: number
        },
        Relationships: []
      },
      statistical_unit_facet_staging: {
        Row: {
          count: number
          legal_form_id: number | null
          partition_seq: number
          physical_country_id: number | null
          physical_region_path: string | null
          primary_activity_category_path: string | null
          sector_path: string | null
          stats_summary: Json | null
          status_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from: string | null
          valid_to: string | null
          valid_until: string | null
        },
        Insert: {
          count: number
          legal_form_id?: number | null
          partition_seq: number
          physical_country_id?: number | null
          physical_region_path?: string | null
          primary_activity_category_path?: string | null
          sector_path?: string | null
          stats_summary?: Json | null
          status_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Update: {
          count?: number
          legal_form_id?: number | null
          partition_seq?: number
          physical_country_id?: number | null
          physical_region_path?: string | null
          primary_activity_category_path?: string | null
          sector_path?: string | null
          stats_summary?: Json | null
          status_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: []
      },
      statistical_unit_staging: {
        Row: {
          activity_category_paths: string[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          domestic: boolean | null
          email_address: string | null
          excluded_enterprise_ids: number[] | null
          excluded_establishment_ids: number[] | null
          excluded_legal_unit_ids: number[] | null
          external_idents: Json | null
          fax_number: string | null
          has_legal_unit: boolean | null
          included_enterprise_count: number | null
          included_enterprise_ids: number[] | null
          included_establishment_count: number | null
          included_establishment_ids: number[] | null
          included_legal_unit_count: number | null
          included_legal_unit_ids: number[] | null
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
          physical_region_path: string | null
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
          postal_region_path: string | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: string | null
          related_enterprise_ids: number[] | null
          related_establishment_ids: number[] | null
          related_legal_unit_ids: number[] | null
          report_partition_seq: number | null
          search: string | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: string | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: string | null
          stats: Json | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          tag_paths: string[] | null
          unit_id: number
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          used_for_counting: boolean | null
          valid_from: string | null
          valid_to: string | null
          valid_until: string | null
          web_address: string | null
        },
        Insert: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          external_idents?: Json | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_count?: number | null
          included_enterprise_ids?: number[] | null
          included_establishment_count?: number | null
          included_establishment_ids?: number[] | null
          included_legal_unit_count?: number | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          report_partition_seq?: number | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          tag_paths?: string[] | null
          unit_id: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          used_for_counting?: boolean | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
        Update: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          external_idents?: Json | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_count?: number | null
          included_enterprise_ids?: number[] | null
          included_establishment_count?: number | null
          included_establishment_ids?: number[] | null
          included_legal_unit_count?: number | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          report_partition_seq?: number | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          tag_paths?: string[] | null
          unit_id?: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          used_for_counting?: boolean | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
        Relationships: []
      },
      status: {
        Row: {
          assigned_by_default: boolean
          code: string
          created_at: string
          custom: boolean
          enabled: boolean
          id: number
          name: string
          priority: number
          updated_at: string
          used_for_counting: boolean
        },
        Insert: {
          assigned_by_default: boolean
          code: string
          created_at?: string
          custom?: boolean
          enabled: boolean
          id?: never
          name: string
          priority: number
          updated_at?: string
          used_for_counting: boolean
        },
        Update: {
          assigned_by_default?: boolean
          code?: string
          created_at?: string
          custom?: boolean
          enabled?: boolean
          id?: never
          name?: string
          priority?: number
          updated_at?: string
          used_for_counting?: boolean
        },
        Relationships: []
      },
      tag: {
        Row: {
          code: string | null
          context_valid_from: string | null
          context_valid_on: string | null
          context_valid_to: string | null
          context_valid_until: string | null
          created_at: string
          description: string | null
          enabled: boolean
          id: number
          label: string
          level: number | null
          name: string
          parent_id: number | null
          path: string
          type: Database["public"]["Enums"]["tag_type"]
          updated_at: string
        },
        Insert: {
          code?: string | null
          context_valid_from?: string | null
          context_valid_on?: string | null
          context_valid_to?: string | null
          context_valid_until?: string | null
          created_at?: string
          description?: string | null
          enabled?: boolean
          id?: never
          label: string
          level?: number | null
          name: string
          parent_id?: number | null
          path: string
          type: Database["public"]["Enums"]["tag_type"]
          updated_at?: string
        },
        Update: {
          code?: string | null
          context_valid_from?: string | null
          context_valid_on?: string | null
          context_valid_to?: string | null
          context_valid_until?: string | null
          created_at?: string
          description?: string | null
          enabled?: boolean
          id?: never
          label?: string
          level?: number | null
          name?: string
          parent_id?: number | null
          path?: string
          type?: Database["public"]["Enums"]["tag_type"]
          updated_at?: string
        },
        Relationships: [
          {
            foreignKeyName: "tag_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "tag"
            referencedColumns: ["id"]
          }
        ]
      },
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
        },
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
        },
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
        },
        Relationships: [
          {
            foreignKeyName: "tag_for_unit_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "enterprise"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tag_for_unit_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "tag"
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
            foreignKeyName: "tag_for_unit_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      timeline_enterprise: {
        Row: {
          activity_category_paths: string[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          domestic: boolean | null
          email_address: string | null
          enterprise_id: number | null
          excluded_enterprise_ids: number[] | null
          excluded_establishment_ids: number[] | null
          excluded_legal_unit_ids: number[] | null
          fax_number: string | null
          has_legal_unit: boolean | null
          included_enterprise_ids: number[] | null
          included_establishment_ids: number[] | null
          included_legal_unit_ids: number[] | null
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
          physical_region_path: string | null
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
          postal_region_path: string | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: string | null
          primary_establishment_id: number | null
          primary_legal_unit_id: number | null
          related_enterprise_ids: number[] | null
          related_establishment_ids: number[] | null
          related_legal_unit_ids: number[] | null
          search: string | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: string | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: string | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          unit_id: number
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          used_for_counting: boolean | null
          valid_from: string
          valid_to: string
          valid_until: string
          web_address: string | null
        },
        Insert: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          enterprise_id?: number | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_ids?: number[] | null
          included_establishment_ids?: number[] | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          primary_establishment_id?: number | null
          primary_legal_unit_id?: number | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          used_for_counting?: boolean | null
          valid_from: string
          valid_to: string
          valid_until: string
          web_address?: string | null
        },
        Update: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          enterprise_id?: number | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_ids?: number[] | null
          included_establishment_ids?: number[] | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          primary_establishment_id?: number | null
          primary_legal_unit_id?: number | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id?: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          used_for_counting?: boolean | null
          valid_from?: string
          valid_to?: string
          valid_until?: string
          web_address?: string | null
        },
        Relationships: []
      },
      timeline_establishment: {
        Row: {
          activity_category_paths: string[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          domestic: boolean | null
          email_address: string | null
          enterprise_id: number | null
          establishment_id: number | null
          excluded_enterprise_ids: number[] | null
          excluded_establishment_ids: number[] | null
          excluded_legal_unit_ids: number[] | null
          fax_number: string | null
          has_legal_unit: boolean | null
          included_enterprise_ids: number[] | null
          included_establishment_ids: number[] | null
          included_legal_unit_ids: number[] | null
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
          physical_region_path: string | null
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
          postal_region_path: string | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: string | null
          primary_for_enterprise: boolean | null
          primary_for_legal_unit: boolean | null
          related_enterprise_ids: number[] | null
          related_establishment_ids: number[] | null
          related_legal_unit_ids: number[] | null
          search: string | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: string | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: string | null
          stats: Json | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          unit_id: number
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          used_for_counting: boolean | null
          valid_from: string
          valid_to: string
          valid_until: string
          web_address: string | null
        },
        Insert: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          enterprise_id?: number | null
          establishment_id?: number | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_ids?: number[] | null
          included_establishment_ids?: number[] | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          primary_for_enterprise?: boolean | null
          primary_for_legal_unit?: boolean | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          used_for_counting?: boolean | null
          valid_from: string
          valid_to: string
          valid_until: string
          web_address?: string | null
        },
        Update: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          enterprise_id?: number | null
          establishment_id?: number | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_ids?: number[] | null
          included_establishment_ids?: number[] | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          primary_for_enterprise?: boolean | null
          primary_for_legal_unit?: boolean | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id?: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          used_for_counting?: boolean | null
          valid_from?: string
          valid_to?: string
          valid_until?: string
          web_address?: string | null
        },
        Relationships: []
      },
      timeline_legal_unit: {
        Row: {
          activity_category_paths: string[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          domestic: boolean | null
          email_address: string | null
          enterprise_id: number | null
          excluded_enterprise_ids: number[] | null
          excluded_establishment_ids: number[] | null
          excluded_legal_unit_ids: number[] | null
          fax_number: string | null
          has_legal_unit: boolean | null
          included_enterprise_ids: number[] | null
          included_establishment_ids: number[] | null
          included_legal_unit_ids: number[] | null
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
          physical_region_path: string | null
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
          postal_region_path: string | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: string | null
          primary_for_enterprise: boolean | null
          related_enterprise_ids: number[] | null
          related_establishment_ids: number[] | null
          related_legal_unit_ids: number[] | null
          search: string | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: string | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: string | null
          stats: Json | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          unit_id: number
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          used_for_counting: boolean | null
          valid_from: string
          valid_to: string
          valid_until: string
          web_address: string | null
        },
        Insert: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          enterprise_id?: number | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_ids?: number[] | null
          included_establishment_ids?: number[] | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          primary_for_enterprise?: boolean | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          used_for_counting?: boolean | null
          valid_from: string
          valid_to: string
          valid_until: string
          web_address?: string | null
        },
        Update: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          enterprise_id?: number | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_ids?: number[] | null
          included_establishment_ids?: number[] | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          primary_for_enterprise?: boolean | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id?: number
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          used_for_counting?: boolean | null
          valid_from?: string
          valid_to?: string
          valid_until?: string
          web_address?: string | null
        },
        Relationships: []
      },
      timepoints: {
        Row: {
          timepoint: string
          unit_id: number
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
        },
        Insert: {
          timepoint: string
          unit_id: number
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
        },
        Update: {
          timepoint?: string
          unit_id?: number
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
        },
        Relationships: []
      },
      timesegments: {
        Row: {
          unit_id: number
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          valid_from: string
          valid_until: string
        },
        Insert: {
          unit_id: number
          unit_type: Database["public"]["Enums"]["statistical_unit_type"]
          valid_from: string
          valid_until: string
        },
        Update: {
          unit_id?: number
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          valid_from?: string
          valid_until?: string
        },
        Relationships: []
      },
      timesegments_years: {
        Row: {
          year: number
        },
        Insert: {
          year: number
        },
        Update: {
          year?: number
        },
        Relationships: []
      },
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
        },
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
        },
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
        },
        Relationships: [
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
          {
            foreignKeyName: "unit_notes_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      unit_size: {
        Row: {
          code: string
          created_at: string
          custom: boolean
          enabled: boolean
          id: number
          name: string
          updated_at: string
        },
        Insert: {
          code: string
          created_at?: string
          custom: boolean
          enabled: boolean
          id?: never
          name: string
          updated_at?: string
        },
        Update: {
          code?: string
          created_at?: string
          custom?: boolean
          enabled?: boolean
          id?: never
          name?: string
          updated_at?: string
        },
        Relationships: []
      }
    },
    Views: {
      activity__for_portion_of_valid: {
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
          valid_from: string | null
          valid_range: string | null
          valid_to: string | null
          valid_until: string | null
        },
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
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
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
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "activity_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
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
            foreignKeyName: "activity_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "activity_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit"
            referencedColumns: ["id", "valid_range"]
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
            foreignKeyName: "activity_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["establishment_id"]
          },
          {
            foreignKeyName: "activity_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["legal_unit_id"]
          },
          {
            foreignKeyName: "activity_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      activity_category_available: {
        Row: {
          code: string | null
          custom: boolean | null
          description: string | null
          id: number | null
          label: string | null
          name: string | null
          parent_path: string | null
          path: string | null
          standard_code: string | null
        },
        Insert: {
          code?: string | null
          custom?: boolean | null
          description?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_path?: string | null
          path?: string | null
          standard_code?: string | null
        },
        Update: {
          code?: string | null
          custom?: boolean | null
          description?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_path?: string | null
          path?: string | null
          standard_code?: string | null
        },
        Relationships: []
      },
      activity_category_available_custom: {
        Row: {
          description: string | null
          name: string | null
          path: string | null
        },
        Insert: {
          description?: string | null
          name?: string | null
          path?: string | null
        },
        Update: {
          description?: string | null
          name?: string | null
          path?: string | null
        },
        Relationships: []
      },
      activity_category_isic_v4: {
        Row: {
          code: string | null
          description: string | null
          label: string | null
          name: string | null
          path: string | null
          standard: string | null
        },
        Insert: {
          code?: string | null
          description?: string | null
          label?: string | null
          name?: string | null
          path?: string | null
          standard?: string | null
        },
        Update: {
          code?: string | null
          description?: string | null
          label?: string | null
          name?: string | null
          path?: string | null
          standard?: string | null
        },
        Relationships: []
      },
      activity_category_nace_v2_1: {
        Row: {
          code: string | null
          description: string | null
          label: string | null
          name: string | null
          path: string | null
          standard: string | null
        },
        Insert: {
          code?: string | null
          description?: string | null
          label?: string | null
          name?: string | null
          path?: string | null
          standard?: string | null
        },
        Update: {
          code?: string | null
          description?: string | null
          label?: string | null
          name?: string | null
          path?: string | null
          standard?: string | null
        },
        Relationships: []
      },
      activity_category_used_def: {
        Row: {
          code: string | null
          description: string | null
          id: number | null
          label: string | null
          name: string | null
          parent_path: string | null
          path: string | null
          standard_code: string | null
        },
        Insert: {
          code?: string | null
          description?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_path?: string | null
          path?: string | null
          standard_code?: string | null
        },
        Update: {
          code?: string | null
          description?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_path?: string | null
          path?: string | null
          standard_code?: string | null
        },
        Relationships: []
      },
      api_key: {
        Row: {
          created_at: string | null
          description: string | null
          expires_at: string | null
          id: number | null
          jti: string | null
          revoked_at: string | null
          token: string | null
          user_id: number | null
        },
        Insert: {
          created_at?: string | null
          description?: string | null
          expires_at?: string | null
          id?: number | null
          jti?: string | null
          revoked_at?: string | null
          token?: string | null
          user_id?: number | null
        },
        Update: {
          created_at?: string | null
          description?: string | null
          expires_at?: string | null
          id?: number | null
          jti?: string | null
          revoked_at?: string | null
          token?: string | null
          user_id?: number | null
        },
        Relationships: [
          {
            foreignKeyName: "api_key_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      contact__for_portion_of_valid: {
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
          valid_from: string | null
          valid_range: string | null
          valid_to: string | null
          valid_until: string | null
          web_address: string | null
        },
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
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
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
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "contact_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contact_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "contact_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit"
            referencedColumns: ["id", "valid_range"]
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
            foreignKeyName: "contact_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contact_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contact_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["establishment_id"]
          },
          {
            foreignKeyName: "contact_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["legal_unit_id"]
          },
          {
            foreignKeyName: "contact_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      country_used_def: {
        Row: {
          id: number | null
          iso_2: string | null
          name: string | null
        },
        Insert: {
          id?: number | null
          iso_2?: string | null
          name?: string | null
        },
        Update: {
          id?: number | null
          iso_2?: string | null
          name?: string | null
        },
        Relationships: []
      },
      country_view: {
        Row: {
          custom: boolean | null
          enabled: boolean | null
          id: number | null
          iso_2: string | null
          iso_3: string | null
          iso_num: string | null
          name: string | null
        },
        Insert: {
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          iso_2?: string | null
          iso_3?: string | null
          iso_num?: string | null
          name?: string | null
        },
        Update: {
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          iso_2?: string | null
          iso_3?: string | null
          iso_num?: string | null
          name?: string | null
        },
        Relationships: []
      },
      data_source_available: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      data_source_custom: {
        Row: {
          code: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          name?: string | null
        },
        Relationships: []
      },
      data_source_ordered: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      data_source_system: {
        Row: {
          code: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          name?: string | null
        },
        Relationships: []
      },
      data_source_used_def: {
        Row: {
          code: string | null
          id: number | null
          name: string | null
        },
        Insert: {
          code?: string | null
          id?: number | null
          name?: string | null
        },
        Update: {
          code?: string | null
          id?: number | null
          name?: string | null
        },
        Relationships: []
      },
      enterprise_external_idents: {
        Row: {
          external_idents: Json | null
          unit_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from: string | null
          valid_to: string | null
          valid_until: string | null
        },
        Insert: {
          external_idents?: Json | null
          unit_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Update: {
          external_idents?: Json | null
          unit_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: []
      },
      enterprise_group__for_portion_of_valid: {
        Row: {
          contact_person: string | null
          data_source_id: number | null
          edit_at: string | null
          edit_by_user_id: number | null
          edit_comment: string | null
          enterprise_group_type_id: number | null
          foreign_participation_id: number | null
          id: number | null
          name: string | null
          reorg_date: string | null
          reorg_references: string | null
          reorg_type_id: number | null
          short_name: string | null
          unit_size_id: number | null
          valid_from: string | null
          valid_range: string | null
          valid_to: string | null
          valid_until: string | null
        },
        Insert: {
          contact_person?: string | null
          data_source_id?: number | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          enterprise_group_type_id?: number | null
          foreign_participation_id?: number | null
          id?: number | null
          name?: string | null
          reorg_date?: string | null
          reorg_references?: string | null
          reorg_type_id?: number | null
          short_name?: string | null
          unit_size_id?: number | null
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Update: {
          contact_person?: string | null
          data_source_id?: number | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          enterprise_group_type_id?: number | null
          foreign_participation_id?: number | null
          id?: number | null
          name?: string | null
          reorg_date?: string | null
          reorg_references?: string | null
          reorg_type_id?: number | null
          short_name?: string | null
          unit_size_id?: number | null
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "enterprise_group_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
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
            foreignKeyName: "enterprise_group_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation"
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
            foreignKeyName: "enterprise_group_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size"
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
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["unit_size_id"]
          },
          {
            foreignKeyName: "enterprise_group_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["unit_size_id"]
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
          {
            foreignKeyName: "enterprise_group_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      enterprise_group_role_available: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      enterprise_group_role_custom: {
        Row: {
          code: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          name?: string | null
        },
        Relationships: []
      },
      enterprise_group_role_ordered: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      enterprise_group_role_system: {
        Row: {
          code: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          name?: string | null
        },
        Relationships: []
      },
      enterprise_group_type_available: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      enterprise_group_type_custom: {
        Row: {
          code: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          name?: string | null
        },
        Relationships: []
      },
      enterprise_group_type_ordered: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      enterprise_group_type_system: {
        Row: {
          code: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          name?: string | null
        },
        Relationships: []
      },
      establishment__for_portion_of_valid: {
        Row: {
          birth_date: string | null
          data_source_id: number | null
          death_date: string | null
          edit_at: string | null
          edit_by_user_id: number | null
          edit_comment: string | null
          enterprise_id: number | null
          free_econ_zone: boolean | null
          id: number | null
          image_id: number | null
          legal_unit_id: number | null
          name: string | null
          primary_for_enterprise: boolean | null
          primary_for_legal_unit: boolean | null
          sector_id: number | null
          short_name: string | null
          status_id: number | null
          unit_size_id: number | null
          valid_from: string | null
          valid_range: string | null
          valid_to: string | null
          valid_until: string | null
        },
        Insert: {
          birth_date?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          enterprise_id?: number | null
          free_econ_zone?: boolean | null
          id?: number | null
          image_id?: number | null
          legal_unit_id?: number | null
          name?: string | null
          primary_for_enterprise?: boolean | null
          primary_for_legal_unit?: boolean | null
          sector_id?: number | null
          short_name?: string | null
          status_id?: number | null
          unit_size_id?: number | null
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Update: {
          birth_date?: string | null
          data_source_id?: number | null
          death_date?: string | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          enterprise_id?: number | null
          free_econ_zone?: boolean | null
          id?: number | null
          image_id?: number | null
          legal_unit_id?: number | null
          name?: string | null
          primary_for_enterprise?: boolean | null
          primary_for_legal_unit?: boolean | null
          sector_id?: number | null
          short_name?: string | null
          status_id?: number | null
          unit_size_id?: number | null
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "establishment_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
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
            foreignKeyName: "establishment_image_id_fkey"
            columns: ["image_id"]
            isOneToOne: false
            referencedRelation: "image"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "establishment_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "establishment_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector"
            referencedColumns: ["id"]
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
            foreignKeyName: "establishment_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit__for_portion_of_valid"
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
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "establishment_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["status_id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["unit_size_id"]
          },
          {
            foreignKeyName: "establishment_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["legal_unit_id"]
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
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["status_id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["unit_size_id"]
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
            foreignKeyName: "establishment_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      external_ident_type_active: {
        Row: {
          code: string | null
          description: string | null
          enabled: boolean | null
          id: number | null
          labels: string | null
          name: string | null
          priority: number | null
          shape: Database["public"]["Enums"]["external_ident_shape"] | null
        },
        Insert: {
          code?: string | null
          description?: string | null
          enabled?: boolean | null
          id?: number | null
          labels?: string | null
          name?: string | null
          priority?: number | null
          shape?: Database["public"]["Enums"]["external_ident_shape"] | null
        },
        Update: {
          code?: string | null
          description?: string | null
          enabled?: boolean | null
          id?: number | null
          labels?: string | null
          name?: string | null
          priority?: number | null
          shape?: Database["public"]["Enums"]["external_ident_shape"] | null
        },
        Relationships: []
      },
      external_ident_type_ordered: {
        Row: {
          code: string | null
          description: string | null
          enabled: boolean | null
          id: number | null
          labels: string | null
          name: string | null
          priority: number | null
          shape: Database["public"]["Enums"]["external_ident_shape"] | null
        },
        Insert: {
          code?: string | null
          description?: string | null
          enabled?: boolean | null
          id?: number | null
          labels?: string | null
          name?: string | null
          priority?: number | null
          shape?: Database["public"]["Enums"]["external_ident_shape"] | null
        },
        Update: {
          code?: string | null
          description?: string | null
          enabled?: boolean | null
          id?: number | null
          labels?: string | null
          name?: string | null
          priority?: number | null
          shape?: Database["public"]["Enums"]["external_ident_shape"] | null
        },
        Relationships: []
      },
      foreign_participation_available: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      foreign_participation_custom: {
        Row: {
          code: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          name?: string | null
        },
        Relationships: []
      },
      foreign_participation_ordered: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      foreign_participation_system: {
        Row: {
          code: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          name?: string | null
        },
        Relationships: []
      },
      hypopg_hidden_indexes: {
        Row: {
          am_name: string | null
          index_name: string | null
          indexrelid: number | null
          is_hypo: boolean | null
          schema_name: string | null
          table_name: string | null
        },
        Insert: {
          am_name?: string | null
          index_name?: string | null
          indexrelid?: number | null
          is_hypo?: boolean | null
          schema_name?: string | null
          table_name?: string | null
        },
        Update: {
          am_name?: string | null
          index_name?: string | null
          indexrelid?: number | null
          is_hypo?: boolean | null
          schema_name?: string | null
          table_name?: string | null
        },
        Relationships: []
      },
      hypopg_list_indexes: {
        Row: {
          am_name: string | null
          index_name: string | null
          indexrelid: number | null
          schema_name: string | null
          table_name: string | null
        },
        Insert: {
          am_name?: string | null
          index_name?: string | null
          indexrelid?: number | null
          schema_name?: string | null
          table_name?: string | null
        },
        Update: {
          am_name?: string | null
          index_name?: string | null
          indexrelid?: number | null
          schema_name?: string | null
          table_name?: string | null
        },
        Relationships: []
      },
      legal_form_available: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      legal_form_custom: {
        Row: {
          code: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          name?: string | null
        },
        Relationships: []
      },
      legal_form_custom_only: {
        Row: {
          code: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          name?: string | null
        },
        Relationships: []
      },
      legal_form_ordered: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      legal_form_system: {
        Row: {
          code: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          name?: string | null
        },
        Relationships: []
      },
      legal_form_used_def: {
        Row: {
          code: string | null
          id: number | null
          name: string | null
        },
        Insert: {
          code?: string | null
          id?: number | null
          name?: string | null
        },
        Update: {
          code?: string | null
          id?: number | null
          name?: string | null
        },
        Relationships: []
      },
      legal_unit__for_portion_of_valid: {
        Row: {
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
          image_id: number | null
          legal_form_id: number | null
          name: string | null
          primary_for_enterprise: boolean | null
          sector_id: number | null
          short_name: string | null
          status_id: number | null
          unit_size_id: number | null
          valid_from: string | null
          valid_range: string | null
          valid_to: string | null
          valid_until: string | null
        },
        Insert: {
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
          image_id?: number | null
          legal_form_id?: number | null
          name?: string | null
          primary_for_enterprise?: boolean | null
          sector_id?: number | null
          short_name?: string | null
          status_id?: number | null
          unit_size_id?: number | null
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Update: {
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
          image_id?: number | null
          legal_form_id?: number | null
          name?: string | null
          primary_for_enterprise?: boolean | null
          sector_id?: number | null
          short_name?: string | null
          status_id?: number | null
          unit_size_id?: number | null
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "legal_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
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
            foreignKeyName: "legal_unit_foreign_participation_id_fkey"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_unit_image_id_fkey"
            columns: ["image_id"]
            isOneToOne: false
            referencedRelation: "image"
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
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector"
            referencedColumns: ["id"]
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
            foreignKeyName: "legal_unit_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise_def"
            referencedColumns: ["enterprise_id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "legal_unit_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["status_id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["unit_size_id"]
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
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "legal_unit_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["status_id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["unit_size_id"]
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
            foreignKeyName: "legal_unit_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      location__for_portion_of_valid: {
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
          valid_from: string | null
          valid_range: string | null
          valid_to: string | null
          valid_until: string | null
        },
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
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
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
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "location_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country"
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
            foreignKeyName: "location_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "location_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "region"
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
            foreignKeyName: "location_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "region_used_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["establishment_id"]
          },
          {
            foreignKeyName: "location_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["legal_unit_id"]
          },
          {
            foreignKeyName: "location_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      person_for_unit__for_portion_of_valid: {
        Row: {
          data_source_id: number | null
          edit_at: string | null
          edit_by_user_id: number | null
          edit_comment: string | null
          establishment_id: number | null
          id: number | null
          legal_unit_id: number | null
          person_id: number | null
          person_role_id: number | null
          valid_from: string | null
          valid_range: string | null
          valid_to: string | null
          valid_until: string | null
        },
        Insert: {
          data_source_id?: number | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number | null
          legal_unit_id?: number | null
          person_id?: number | null
          person_role_id?: number | null
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Update: {
          data_source_id?: number | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number | null
          legal_unit_id?: number | null
          person_id?: number | null
          person_role_id?: number | null
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "person_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_for_unit_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "person_for_unit_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit"
            referencedColumns: ["id", "valid_range"]
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
            foreignKeyName: "person_for_unit_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_for_unit_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit__for_portion_of_valid"
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
          {
            foreignKeyName: "person_for_unit_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["establishment_id"]
          },
          {
            foreignKeyName: "person_for_unit_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["legal_unit_id"]
          },
          {
            foreignKeyName: "person_for_unit_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      person_role_available: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      person_role_custom: {
        Row: {
          code: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          name?: string | null
        },
        Relationships: []
      },
      person_role_ordered: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      person_role_system: {
        Row: {
          code: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          name?: string | null
        },
        Relationships: []
      },
      region_upload: {
        Row: {
          center_altitude: string | null
          center_latitude: string | null
          center_longitude: string | null
          name: string | null
          path: string | null
        },
        Insert: {
          center_altitude?: string | null
          center_latitude?: string | null
          center_longitude?: string | null
          name?: string | null
          path?: string | null
        },
        Update: {
          center_altitude?: string | null
          center_latitude?: string | null
          center_longitude?: string | null
          name?: string | null
          path?: string | null
        },
        Relationships: []
      },
      region_used_def: {
        Row: {
          code: string | null
          id: number | null
          label: string | null
          level: number | null
          name: string | null
          path: string | null
        },
        Insert: {
          code?: string | null
          id?: number | null
          label?: string | null
          level?: number | null
          name?: string | null
          path?: string | null
        },
        Update: {
          code?: string | null
          id?: number | null
          label?: string | null
          level?: number | null
          name?: string | null
          path?: string | null
        },
        Relationships: []
      },
      relative_period_with_time: {
        Row: {
          code: Database["public"]["Enums"]["relative_period_code"] | null
          enabled: boolean | null
          id: number | null
          name_when_input: string | null
          name_when_query: string | null
          scope: Database["public"]["Enums"]["relative_period_scope"] | null
          valid_from: string | null
          valid_on: string | null
          valid_to: string | null
        },
        Insert: {
          code?: Database["public"]["Enums"]["relative_period_code"] | null
          enabled?: boolean | null
          id?: number | null
          name_when_input?: string | null
          name_when_query?: string | null
          scope?: Database["public"]["Enums"]["relative_period_scope"] | null
          valid_from?: string | null
          valid_on?: string | null
          valid_to?: string | null
        },
        Update: {
          code?: Database["public"]["Enums"]["relative_period_code"] | null
          enabled?: boolean | null
          id?: number | null
          name_when_input?: string | null
          name_when_query?: string | null
          scope?: Database["public"]["Enums"]["relative_period_scope"] | null
          valid_from?: string | null
          valid_on?: string | null
          valid_to?: string | null
        },
        Relationships: []
      },
      reorg_type_available: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          description: string | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      reorg_type_custom: {
        Row: {
          code: string | null
          description: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          description?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          description?: string | null
          name?: string | null
        },
        Relationships: []
      },
      reorg_type_ordered: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          description: string | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      reorg_type_system: {
        Row: {
          code: string | null
          description: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          description?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          description?: string | null
          name?: string | null
        },
        Relationships: []
      },
      sector_available: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          description: string | null
          enabled: boolean | null
          id: number | null
          label: string | null
          name: string | null
          parent_id: number | null
          path: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          enabled?: boolean | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_id?: number | null
          path?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          enabled?: boolean | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_id?: number | null
          path?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      sector_custom: {
        Row: {
          description: string | null
          name: string | null
          path: string | null
        },
        Insert: {
          description?: string | null
          name?: string | null
          path?: string | null
        },
        Update: {
          description?: string | null
          name?: string | null
          path?: string | null
        },
        Relationships: []
      },
      sector_custom_only: {
        Row: {
          description: string | null
          name: string | null
          path: string | null
        },
        Insert: {
          description?: string | null
          name?: string | null
          path?: string | null
        },
        Update: {
          description?: string | null
          name?: string | null
          path?: string | null
        },
        Relationships: []
      },
      sector_ordered: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          description: string | null
          enabled: boolean | null
          id: number | null
          label: string | null
          name: string | null
          parent_id: number | null
          path: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          enabled?: boolean | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_id?: number | null
          path?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          description?: string | null
          enabled?: boolean | null
          id?: number | null
          label?: string | null
          name?: string | null
          parent_id?: number | null
          path?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      sector_system: {
        Row: {
          description: string | null
          name: string | null
          path: string | null
        },
        Insert: {
          description?: string | null
          name?: string | null
          path?: string | null
        },
        Update: {
          description?: string | null
          name?: string | null
          path?: string | null
        },
        Relationships: []
      },
      sector_used_def: {
        Row: {
          code: string | null
          id: number | null
          label: string | null
          name: string | null
          path: string | null
        },
        Insert: {
          code?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          path?: string | null
        },
        Update: {
          code?: string | null
          id?: number | null
          label?: string | null
          name?: string | null
          path?: string | null
        },
        Relationships: []
      },
      stat_definition_active: {
        Row: {
          code: string | null
          description: string | null
          enabled: boolean | null
          frequency: Database["public"]["Enums"]["stat_frequency"] | null
          id: number | null
          name: string | null
          priority: number | null
          type: Database["public"]["Enums"]["stat_type"] | null
        },
        Insert: {
          code?: string | null
          description?: string | null
          enabled?: boolean | null
          frequency?: Database["public"]["Enums"]["stat_frequency"] | null
          id?: number | null
          name?: string | null
          priority?: number | null
          type?: Database["public"]["Enums"]["stat_type"] | null
        },
        Update: {
          code?: string | null
          description?: string | null
          enabled?: boolean | null
          frequency?: Database["public"]["Enums"]["stat_frequency"] | null
          id?: number | null
          name?: string | null
          priority?: number | null
          type?: Database["public"]["Enums"]["stat_type"] | null
        },
        Relationships: []
      },
      stat_definition_ordered: {
        Row: {
          code: string | null
          description: string | null
          enabled: boolean | null
          frequency: Database["public"]["Enums"]["stat_frequency"] | null
          id: number | null
          name: string | null
          priority: number | null
          type: Database["public"]["Enums"]["stat_type"] | null
        },
        Insert: {
          code?: string | null
          description?: string | null
          enabled?: boolean | null
          frequency?: Database["public"]["Enums"]["stat_frequency"] | null
          id?: number | null
          name?: string | null
          priority?: number | null
          type?: Database["public"]["Enums"]["stat_type"] | null
        },
        Update: {
          code?: string | null
          description?: string | null
          enabled?: boolean | null
          frequency?: Database["public"]["Enums"]["stat_frequency"] | null
          id?: number | null
          name?: string | null
          priority?: number | null
          type?: Database["public"]["Enums"]["stat_type"] | null
        },
        Relationships: []
      },
      stat_for_unit__for_portion_of_valid: {
        Row: {
          data_source_id: number | null
          edit_at: string | null
          edit_by_user_id: number | null
          edit_comment: string | null
          establishment_id: number | null
          id: number | null
          legal_unit_id: number | null
          stat_definition_id: number | null
          valid_from: string | null
          valid_range: string | null
          valid_to: string | null
          valid_until: string | null
          value_bool: boolean | null
          value_float: number | null
          value_int: number | null
          value_string: string | null
        },
        Insert: {
          data_source_id?: number | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number | null
          legal_unit_id?: number | null
          stat_definition_id?: number | null
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
          value_bool?: boolean | null
          value_float?: number | null
          value_int?: number | null
          value_string?: string | null
        },
        Update: {
          data_source_id?: number | null
          edit_at?: string | null
          edit_by_user_id?: number | null
          edit_comment?: string | null
          establishment_id?: number | null
          id?: number | null
          legal_unit_id?: number | null
          stat_definition_id?: number | null
          valid_from?: string | null
          valid_range?: string | null
          valid_to?: string | null
          valid_until?: string | null
          value_bool?: boolean | null
          value_float?: number | null
          value_int?: number | null
          value_string?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "stat_for_unit_data_source_id_fkey"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "stat_for_unit_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit"
            referencedColumns: ["id", "valid_range"]
          },
          {
            foreignKeyName: "stat_for_unit_stat_definition_id_fkey"
            columns: ["stat_definition_id"]
            isOneToOne: false
            referencedRelation: "stat_definition"
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
            foreignKeyName: "stat_for_unit_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "establishment__for_portion_of_valid"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stat_for_unit_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "legal_unit__for_portion_of_valid"
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
          {
            foreignKeyName: "stat_for_unit_establishment_id_valid"
            columns: ["establishment_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["establishment_id"]
          },
          {
            foreignKeyName: "stat_for_unit_legal_unit_id_valid"
            columns: ["legal_unit_id", "valid_range"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["legal_unit_id"]
          },
          {
            foreignKeyName: "stat_for_unit_edit_by_user_id_fkey"
            columns: ["edit_by_user_id"]
            isOneToOne: false
            referencedRelation: "user"
            referencedColumns: ["id"]
          }
        ]
      },
      statistical_unit_def: {
        Row: {
          activity_category_paths: string[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          domestic: boolean | null
          email_address: string | null
          excluded_enterprise_ids: number[] | null
          excluded_establishment_ids: number[] | null
          excluded_legal_unit_ids: number[] | null
          external_idents: Json | null
          fax_number: string | null
          has_legal_unit: boolean | null
          included_enterprise_count: number | null
          included_enterprise_ids: number[] | null
          included_establishment_count: number | null
          included_establishment_ids: number[] | null
          included_legal_unit_count: number | null
          included_legal_unit_ids: number[] | null
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
          physical_region_path: string | null
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
          postal_region_path: string | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: string | null
          related_enterprise_ids: number[] | null
          related_establishment_ids: number[] | null
          related_legal_unit_ids: number[] | null
          search: string | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: string | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: string | null
          stats: Json | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          tag_paths: string[] | null
          unit_id: number | null
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          used_for_counting: boolean | null
          valid_from: string | null
          valid_to: string | null
          valid_until: string | null
          web_address: string | null
        },
        Insert: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          external_idents?: Json | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_count?: number | null
          included_enterprise_ids?: number[] | null
          included_establishment_count?: number | null
          included_establishment_ids?: number[] | null
          included_legal_unit_count?: number | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          tag_paths?: string[] | null
          unit_id?: number | null
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          used_for_counting?: boolean | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
        Update: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          external_idents?: Json | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_count?: number | null
          included_enterprise_ids?: number[] | null
          included_establishment_count?: number | null
          included_establishment_ids?: number[] | null
          included_legal_unit_count?: number | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          tag_paths?: string[] | null
          unit_id?: number | null
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          used_for_counting?: boolean | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
        Relationships: []
      },
      statistical_unit_facet_def: {
        Row: {
          count: number | null
          legal_form_id: number | null
          physical_country_id: number | null
          physical_region_path: string | null
          primary_activity_category_path: string | null
          sector_path: string | null
          stats_summary: Json | null
          status_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from: string | null
          valid_to: string | null
          valid_until: string | null
        },
        Insert: {
          count?: number | null
          legal_form_id?: number | null
          physical_country_id?: number | null
          physical_region_path?: string | null
          primary_activity_category_path?: string | null
          sector_path?: string | null
          stats_summary?: Json | null
          status_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Update: {
          count?: number | null
          legal_form_id?: number | null
          physical_country_id?: number | null
          physical_region_path?: string | null
          primary_activity_category_path?: string | null
          sector_path?: string | null
          stats_summary?: Json | null
          status_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
        },
        Relationships: []
      },
      time_context: {
        Row: {
          code: Database["public"]["Enums"]["relative_period_code"] | null
          ident: string | null
          name_when_input: string | null
          name_when_query: string | null
          path: string | null
          scope: Database["public"]["Enums"]["relative_period_scope"] | null
          type: Database["public"]["Enums"]["time_context_type"] | null
          valid_from: string | null
          valid_on: string | null
          valid_to: string | null
        },
        Insert: {
          code?: Database["public"]["Enums"]["relative_period_code"] | null
          ident?: string | null
          name_when_input?: string | null
          name_when_query?: string | null
          path?: string | null
          scope?: Database["public"]["Enums"]["relative_period_scope"] | null
          type?: Database["public"]["Enums"]["time_context_type"] | null
          valid_from?: string | null
          valid_on?: string | null
          valid_to?: string | null
        },
        Update: {
          code?: Database["public"]["Enums"]["relative_period_code"] | null
          ident?: string | null
          name_when_input?: string | null
          name_when_query?: string | null
          path?: string | null
          scope?: Database["public"]["Enums"]["relative_period_scope"] | null
          type?: Database["public"]["Enums"]["time_context_type"] | null
          valid_from?: string | null
          valid_on?: string | null
          valid_to?: string | null
        },
        Relationships: []
      },
      timeline_enterprise_def: {
        Row: {
          activity_category_paths: string[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          domestic: boolean | null
          email_address: string | null
          enterprise_id: number | null
          excluded_enterprise_ids: number[] | null
          excluded_establishment_ids: number[] | null
          excluded_legal_unit_ids: number[] | null
          fax_number: string | null
          has_legal_unit: boolean | null
          included_enterprise_ids: number[] | null
          included_establishment_ids: number[] | null
          included_legal_unit_ids: number[] | null
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
          physical_region_path: string | null
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
          postal_region_path: string | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: string | null
          primary_establishment_id: number | null
          primary_legal_unit_id: number | null
          related_enterprise_ids: number[] | null
          related_establishment_ids: number[] | null
          related_legal_unit_ids: number[] | null
          search: string | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: string | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: string | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          unit_id: number | null
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          used_for_counting: boolean | null
          valid_from: string | null
          valid_to: string | null
          valid_until: string | null
          web_address: string | null
        },
        Insert: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          enterprise_id?: number | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_ids?: number[] | null
          included_establishment_ids?: number[] | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          primary_establishment_id?: number | null
          primary_legal_unit_id?: number | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id?: number | null
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          used_for_counting?: boolean | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
        Update: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          enterprise_id?: number | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_ids?: number[] | null
          included_establishment_ids?: number[] | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          primary_establishment_id?: number | null
          primary_legal_unit_id?: number | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id?: number | null
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          used_for_counting?: boolean | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
        Relationships: []
      },
      timeline_establishment_def: {
        Row: {
          activity_category_paths: string[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          domestic: boolean | null
          email_address: string | null
          enterprise_id: number | null
          establishment_id: number | null
          excluded_enterprise_ids: number[] | null
          excluded_establishment_ids: number[] | null
          excluded_legal_unit_ids: number[] | null
          fax_number: string | null
          has_legal_unit: boolean | null
          included_enterprise_ids: number[] | null
          included_establishment_ids: number[] | null
          included_legal_unit_ids: number[] | null
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
          physical_region_path: string | null
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
          postal_region_path: string | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: string | null
          primary_for_enterprise: boolean | null
          primary_for_legal_unit: boolean | null
          related_enterprise_ids: number[] | null
          related_establishment_ids: number[] | null
          related_legal_unit_ids: number[] | null
          search: string | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: string | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: string | null
          stats: Json | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          unit_id: number | null
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          used_for_counting: boolean | null
          valid_from: string | null
          valid_to: string | null
          valid_until: string | null
          web_address: string | null
        },
        Insert: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          enterprise_id?: number | null
          establishment_id?: number | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_ids?: number[] | null
          included_establishment_ids?: number[] | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          primary_for_enterprise?: boolean | null
          primary_for_legal_unit?: boolean | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id?: number | null
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          used_for_counting?: boolean | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
        Update: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          enterprise_id?: number | null
          establishment_id?: number | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_ids?: number[] | null
          included_establishment_ids?: number[] | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          primary_for_enterprise?: boolean | null
          primary_for_legal_unit?: boolean | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id?: number | null
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          used_for_counting?: boolean | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "establishment_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "enterprise"
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
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "establishment_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["status_id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["unit_size_id"]
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
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["status_id"]
          },
          {
            foreignKeyName: "establishment_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["unit_size_id"]
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
          }
        ]
      },
      timeline_legal_unit_def: {
        Row: {
          activity_category_paths: string[] | null
          birth_date: string | null
          data_source_codes: string[] | null
          data_source_ids: number[] | null
          death_date: string | null
          domestic: boolean | null
          email_address: string | null
          enterprise_id: number | null
          excluded_enterprise_ids: number[] | null
          excluded_establishment_ids: number[] | null
          excluded_legal_unit_ids: number[] | null
          fax_number: string | null
          has_legal_unit: boolean | null
          included_enterprise_ids: number[] | null
          included_establishment_ids: number[] | null
          included_legal_unit_ids: number[] | null
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
          physical_region_path: string | null
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
          postal_region_path: string | null
          primary_activity_category_code: string | null
          primary_activity_category_id: number | null
          primary_activity_category_path: string | null
          primary_for_enterprise: boolean | null
          related_enterprise_ids: number[] | null
          related_establishment_ids: number[] | null
          related_legal_unit_ids: number[] | null
          search: string | null
          secondary_activity_category_code: string | null
          secondary_activity_category_id: number | null
          secondary_activity_category_path: string | null
          sector_code: string | null
          sector_id: number | null
          sector_name: string | null
          sector_path: string | null
          stats: Json | null
          stats_summary: Json | null
          status_code: string | null
          status_id: number | null
          unit_id: number | null
          unit_size_code: string | null
          unit_size_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          used_for_counting: boolean | null
          valid_from: string | null
          valid_to: string | null
          valid_until: string | null
          web_address: string | null
        },
        Insert: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          enterprise_id?: number | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_ids?: number[] | null
          included_establishment_ids?: number[] | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          primary_for_enterprise?: boolean | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id?: number | null
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          used_for_counting?: boolean | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
        Update: {
          activity_category_paths?: string[] | null
          birth_date?: string | null
          data_source_codes?: string[] | null
          data_source_ids?: number[] | null
          death_date?: string | null
          domestic?: boolean | null
          email_address?: string | null
          enterprise_id?: number | null
          excluded_enterprise_ids?: number[] | null
          excluded_establishment_ids?: number[] | null
          excluded_legal_unit_ids?: number[] | null
          fax_number?: string | null
          has_legal_unit?: boolean | null
          included_enterprise_ids?: number[] | null
          included_establishment_ids?: number[] | null
          included_legal_unit_ids?: number[] | null
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
          physical_region_path?: string | null
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
          postal_region_path?: string | null
          primary_activity_category_code?: string | null
          primary_activity_category_id?: number | null
          primary_activity_category_path?: string | null
          primary_for_enterprise?: boolean | null
          related_enterprise_ids?: number[] | null
          related_establishment_ids?: number[] | null
          related_legal_unit_ids?: number[] | null
          search?: string | null
          secondary_activity_category_code?: string | null
          secondary_activity_category_id?: number | null
          secondary_activity_category_path?: string | null
          sector_code?: string | null
          sector_id?: number | null
          sector_name?: string | null
          sector_path?: string | null
          stats?: Json | null
          stats_summary?: Json | null
          status_code?: string | null
          status_id?: number | null
          unit_id?: number | null
          unit_size_code?: string | null
          unit_size_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          used_for_counting?: boolean | null
          valid_from?: string | null
          valid_to?: string | null
          valid_until?: string | null
          web_address?: string | null
        },
        Relationships: [
          {
            foreignKeyName: "legal_unit_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "enterprise"
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
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "sector"
            referencedColumns: ["id"]
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
            foreignKeyName: "legal_unit_enterprise_id_fkey"
            columns: ["enterprise_id"]
            isOneToOne: false
            referencedRelation: "timeline_enterprise_def"
            referencedColumns: ["enterprise_id"]
          },
          {
            foreignKeyName: "legal_unit_sector_id_fkey"
            columns: ["sector_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "legal_unit_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["status_id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "timeline_establishment_def"
            referencedColumns: ["unit_size_id"]
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
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["sector_id"]
          },
          {
            foreignKeyName: "legal_unit_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["status_id"]
          },
          {
            foreignKeyName: "legal_unit_unit_size_id_fkey"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "timeline_legal_unit_def"
            referencedColumns: ["unit_size_id"]
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
          }
        ]
      },
      timesegments_def: {
        Row: {
          unit_id: number | null
          unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from: string | null
          valid_until: string | null
        },
        Insert: {
          unit_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from?: string | null
          valid_until?: string | null
        },
        Update: {
          unit_id?: number | null
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"] | null
          valid_from?: string | null
          valid_until?: string | null
        },
        Relationships: []
      },
      timesegments_years_def: {
        Row: {
          year: number | null
        },
        Insert: {
          year?: number | null
        },
        Update: {
          year?: number | null
        },
        Relationships: []
      },
      unit_size_available: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      unit_size_custom: {
        Row: {
          code: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          name?: string | null
        },
        Relationships: []
      },
      unit_size_ordered: {
        Row: {
          code: string | null
          created_at: string | null
          custom: boolean | null
          enabled: boolean | null
          id: number | null
          name: string | null
          updated_at: string | null
        },
        Insert: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Update: {
          code?: string | null
          created_at?: string | null
          custom?: boolean | null
          enabled?: boolean | null
          id?: number | null
          name?: string | null
          updated_at?: string | null
        },
        Relationships: []
      },
      unit_size_system: {
        Row: {
          code: string | null
          name: string | null
        },
        Insert: {
          code?: string | null
          name?: string | null
        },
        Update: {
          code?: string | null
          name?: string | null
        },
        Relationships: []
      },
      user: {
        Row: {
          created_at: string | null
          deleted_at: string | null
          display_name: string | null
          email: string | null
          email_confirmed_at: string | null
          id: number | null
          last_sign_in_at: string | null
          password: string | null
          statbus_role: Database["public"]["Enums"]["statbus_role"] | null
          sub: string | null
          updated_at: string | null
        },
        Insert: {
          created_at?: string | null
          deleted_at?: string | null
          display_name?: string | null
          email?: string | null
          email_confirmed_at?: string | null
          id?: number | null
          last_sign_in_at?: string | null
          password?: string | null
          statbus_role?: Database["public"]["Enums"]["statbus_role"] | null
          sub?: string | null
          updated_at?: string | null
        },
        Update: {
          created_at?: string | null
          deleted_at?: string | null
          display_name?: string | null
          email?: string | null
          email_confirmed_at?: string | null
          id?: number | null
          last_sign_in_at?: string | null
          password?: string | null
          statbus_role?: Database["public"]["Enums"]["statbus_role"] | null
          sub?: string | null
          updated_at?: string | null
        },
        Relationships: []
      }
    },
    Functions: {
      activity_category_hierarchy: {
        Args: {
          activity_category_id?: number
        }
        Returns: Json
      },
      activity_category_standard_hierarchy: {
        Args: {
          standard_id?: number
        }
        Returns: Json
      },
      activity_category_used_derive: {
        Args: never
        Returns: unknown
      },
      activity_hierarchy: {
        Args: {
          parent_establishment_id?: number
          parent_legal_unit_id?: number
          valid_on?: string
        }
        Returns: Json
      },
      admin_change_password: {
        Args: {
          user_sub?: string
          new_password?: string
        }
        Returns: boolean
      },
      algorithm_sign: {
        Args: {
          signables?: string
          secret?: string
          algorithm?: string
        }
        Returns: string
      },
      array_distinct_concat_final: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      array_to_int4multirange: {
        Args: {
          p_array?: number[]
        }
        Returns: unknown
      },
      auth_expire_access_keep_refresh: {
        Args: never
        Returns: Json
      },
      auth_status: {
        Args: never
        Returns: unknown
      },
      auth_test: {
        Args: never
        Returns: unknown
      },
      bytea_to_text: {
        Args: {
          data?: string
        }
        Returns: string
      },
      cash_dist: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      change_password: {
        Args: {
          new_password?: string
        }
        Returns: boolean
      },
      citext: {
        Args: {
          arg0?: unknown
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: boolean
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: string
        }
        Returns: string
      },
      citext_cmp: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number
      },
      citext_eq: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      citext_ge: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      citext_gt: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      citext_hash: {
        Args: {
          arg0?: string
        }
        Returns: number
      },
      citext_hash_extended: {
        Args: {
          arg0?: string
          arg1?: number
        }
        Returns: number
      },
      citext_larger: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: string
      },
      citext_le: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      citext_lt: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      citext_ne: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      citext_pattern_cmp: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number
      },
      citext_pattern_ge: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      citext_pattern_gt: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      citext_pattern_le: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      citext_pattern_lt: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      citext_smaller: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: string
      },
      citextin: {
        Args: {
          arg0?: unknown
        }
        Returns: string
      },
      citextout: {
        Args: {
          arg0?: string
        }
        Returns: unknown
      },
      citextrecv: {
        Args: {
          arg0?: unknown
        }
        Returns: string
      },
      citextsend: {
        Args: {
          arg0?: string
        }
        Returns: string
      },
      connect_legal_unit_to_enterprise: {
        Args: {
          legal_unit_id?: number
          enterprise_id?: number
          valid_from?: string
          valid_to?: string
        }
        Returns: Json
      },
      contact_hierarchy: {
        Args: {
          parent_establishment_id?: number
          parent_legal_unit_id?: number
          valid_on?: string
        }
        Returns: Json
      },
      country_hierarchy: {
        Args: {
          country_id?: number
        }
        Returns: Json
      },
      country_used_derive: {
        Args: never
        Returns: unknown
      },
      create_api_key: {
        Args: {
          description?: string
          duration?: string
        }
        Returns: Database["public"]["Views"]["api_key"]["Row"]
      },
      crypt: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: string
      },
      data_source_hierarchy: {
        Args: {
          data_source_id?: number
        }
        Returns: Json
      },
      data_source_used_derive: {
        Args: never
        Returns: unknown
      },
      date_dist: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number
      },
      decode_error_level: {
        Args: {
          elevel?: number
        }
        Returns: string
      },
      decrypt: {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: string
        }
        Returns: string
      },
      decrypt_iv: {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: string
          arg3?: string
        }
        Returns: string
      },
      detect_image_type: {
        Args: {
          data?: string
        }
        Returns: string
      },
      digest: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: string
      },
      encrypt: {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: string
        }
        Returns: string
      },
      encrypt_iv: {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: string
          arg3?: string
        }
        Returns: string
      },
      enterprise_hierarchy: {
        Args: {
          enterprise_id?: number
          scope?: Database["public"]["Enums"]["hierarchy_scope"]
          valid_on?: string
        }
        Returns: Json
      },
      establishment_hierarchy: {
        Args: {
          establishment_id?: number
          parent_legal_unit_id?: number
          parent_enterprise_id?: number
          scope?: Database["public"]["Enums"]["hierarchy_scope"]
          valid_on?: string
        }
        Returns: Json
      },
      external_ident_derive_shape_labels: {
        Args: never
        Returns: unknown
      },
      external_idents_hierarchy: {
        Args: {
          parent_establishment_id?: number
          parent_legal_unit_id?: number
          parent_enterprise_id?: number
          parent_enterprise_group_id?: number
        }
        Returns: Json
      },
      fips_mode: {
        Args: never
        Returns: boolean
      },
      float4_dist: {
        Args: {
          arg0?: number
          arg1?: number
        }
        Returns: number
      },
      float8_dist: {
        Args: {
          arg0?: number
          arg1?: number
        }
        Returns: number
      },
      from_to_overlaps: {
        Args: {
          start1?: unknown
          end1?: unknown
          start2?: unknown
          end2?: unknown
        }
        Returns: boolean
      },
      from_until_overlaps: {
        Args: {
          from1?: unknown
          until1?: unknown
          from2?: unknown
          until2?: unknown
        }
        Returns: boolean
      },
      gbt_bit_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_bit_consistent: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_bit_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_bit_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_bit_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_bit_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_bit_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_bool_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_bool_consistent: {
        Args: {
          arg0?: unknown
          arg1?: boolean
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_bool_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_bool_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_bool_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_bool_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_bool_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_bool_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_bpchar_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_bpchar_consistent: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_bpchar_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_bytea_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_bytea_consistent: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_bytea_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_bytea_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_bytea_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_bytea_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_bytea_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_cash_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_cash_consistent: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_cash_distance: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: number
      },
      gbt_cash_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_cash_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_cash_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_cash_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_cash_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_cash_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_date_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_date_consistent: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_date_distance: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: number
      },
      gbt_date_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_date_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_date_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_date_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_date_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_date_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_decompress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_enum_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_enum_consistent: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_enum_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_enum_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_enum_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_enum_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_enum_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_enum_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_float4_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_float4_consistent: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_float4_distance: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: number
      },
      gbt_float4_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_float4_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_float4_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_float4_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_float4_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_float4_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_float8_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_float8_consistent: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_float8_distance: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: number
      },
      gbt_float8_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_float8_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_float8_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_float8_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_float8_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_float8_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_inet_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_inet_consistent: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_inet_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_inet_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_inet_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_inet_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_inet_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_int2_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_int2_consistent: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_int2_distance: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: number
      },
      gbt_int2_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_int2_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_int2_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_int2_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_int2_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_int2_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_int4_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_int4_consistent: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_int4_distance: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: number
      },
      gbt_int4_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_int4_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_int4_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_int4_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_int4_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_int4_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_int8_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_int8_consistent: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_int8_distance: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: number
      },
      gbt_int8_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_int8_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_int8_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_int8_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_int8_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_int8_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_intv_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_intv_consistent: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_intv_decompress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_intv_distance: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: number
      },
      gbt_intv_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_intv_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_intv_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_intv_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_intv_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_intv_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_macad8_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_macad8_consistent: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_macad8_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_macad8_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_macad8_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_macad8_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_macad8_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_macad8_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_macad_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_macad_consistent: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_macad_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_macad_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_macad_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_macad_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_macad_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_macaddr_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_numeric_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_numeric_consistent: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_numeric_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_numeric_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_numeric_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_numeric_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_numeric_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_oid_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_oid_consistent: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_oid_distance: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: number
      },
      gbt_oid_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_oid_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_oid_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_oid_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_oid_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_oid_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_text_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_text_consistent: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_text_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_text_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_text_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_text_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_text_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_time_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_time_consistent: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_time_distance: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: number
      },
      gbt_time_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_time_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_time_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_time_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_time_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_time_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_timetz_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_timetz_consistent: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_ts_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_ts_consistent: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_ts_distance: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: number
      },
      gbt_ts_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_ts_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_ts_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_ts_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_ts_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_ts_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_tstz_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_tstz_consistent: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_tstz_distance: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: number
      },
      gbt_uuid_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_uuid_consistent: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gbt_uuid_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_uuid_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_uuid_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_uuid_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gbt_uuid_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_uuid_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gbt_var_decompress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_var_fetch: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbt_varbit_sortsupport: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbtreekey16_in: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbtreekey16_out: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbtreekey2_in: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbtreekey2_out: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbtreekey32_in: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbtreekey32_out: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbtreekey4_in: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbtreekey4_out: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbtreekey8_in: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbtreekey8_out: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbtreekey_var_in: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gbtreekey_var_out: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gen_random_bytes: {
        Args: {
          arg0?: number
        }
        Returns: string
      },
      gen_random_uuid: {
        Args: never
        Returns: string
      },
      gen_salt: {
        Args: {
          arg0?: string
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: string
          arg1?: number
        }
        Returns: string
      },
      generate_mermaid_er_diagram: {
        Args: never
        Returns: string
      },
      generate_typescript_types: {
        Args: never
        Returns: string
      },
      get_closed_group_batches: {
        Args: {
          p_target_batch_size?: number
          p_establishment_ids?: number[]
          p_legal_unit_ids?: number[]
          p_enterprise_ids?: number[]
          p_offset?: number
          p_limit?: number
        }
        Returns: Record<string, unknown>[]
      },
      get_cmd_type: {
        Args: {
          cmd_type?: number
        }
        Returns: string
      },
      get_enterprise_closed_groups: {
        Args: never
        Returns: Record<string, unknown>[]
      },
      get_external_idents: {
        Args: {
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          unit_id?: number
        }
        Returns: Json
      },
      get_histogram_timings: {
        Args: never
        Returns: string
      },
      get_import_job_progress: {
        Args: {
          job_id?: number
        }
        Returns: Json
      },
      get_statistical_history_periods: {
        Args: {
          p_resolution?: Database["public"]["Enums"]["history_resolution"]
          p_valid_from?: string
          p_valid_until?: string
        }
        Returns: Record<string, unknown>[]
      },
      gin_extract_query_trgm: {
        Args: {
          arg0?: string
          arg1?: unknown
          arg2?: number
          arg3?: unknown
          arg4?: unknown
          arg5?: unknown
          arg6?: unknown
        }
        Returns: unknown
      },
      gin_extract_value_trgm: {
        Args: {
          arg0?: string
          arg1?: unknown
        }
        Returns: unknown
      },
      gin_trgm_consistent: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: string
          arg3?: number
          arg4?: unknown
          arg5?: unknown
          arg6?: unknown
          arg7?: unknown
        }
        Returns: boolean
      },
      gin_trgm_triconsistent: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: string
          arg3?: number
          arg4?: unknown
          arg5?: unknown
          arg6?: unknown
        }
        Returns: string
      },
      gist_translate_cmptype_btree: {
        Args: {
          arg0?: number
        }
        Returns: number
      },
      gtrgm_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gtrgm_consistent: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      gtrgm_decompress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gtrgm_distance: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: number
      },
      gtrgm_in: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gtrgm_options: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gtrgm_out: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      gtrgm_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gtrgm_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      gtrgm_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      gtrgm_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      hash_decode: {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: number
        }
        Returns: number
      },
      hash_encode: {
        Args: {
          arg0?: number
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: number
          arg1?: string
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: number
          arg1?: string
          arg2?: number
        }
        Returns: string
      },
      hash_ltree: {
        Args: {
          arg0?: string
        }
        Returns: number
      },
      hash_ltree_extended: {
        Args: {
          arg0?: string
          arg1?: number
        }
        Returns: number
      },
      histogram: {
        Args: {
          _bucket?: number
          _quryid?: number
        }
        Returns: Record<string, unknown>[]
      },
      hmac: {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: string
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: string
        }
        Returns: string
      },
      http_delete: {
        Args: {
          uri?: string
        }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      }
        | {
        Args: {
          uri?: string
          content?: string
          content_type?: string
        }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      },
      http_get: {
        Args: {
          uri?: string
        }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      }
        | {
        Args: {
          uri?: string
          data?: Json
        }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      },
      http_head: {
        Args: {
          uri?: string
        }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      },
      http_header: {
        Args: {
          field?: string
          value?: string
        }
        Returns: Database["public"]["CompositeTypes"]["http_header"]
      },
      http_list_curlopt: {
        Args: never
        Returns: Record<string, unknown>[]
      },
      http_patch: {
        Args: {
          uri?: string
          content?: string
          content_type?: string
        }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      },
      http_post: {
        Args: {
          uri?: string
          content?: string
          content_type?: string
        }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      }
        | {
        Args: {
          uri?: string
          data?: Json
        }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      },
      http_put: {
        Args: {
          uri?: string
          content?: string
          content_type?: string
        }
        Returns: Database["public"]["CompositeTypes"]["http_response"]
      },
      http_reset_curlopt: {
        Args: never
        Returns: boolean
      },
      http_set_curlopt: {
        Args: {
          curlopt?: string
          value?: string
        }
        Returns: boolean
      },
      hypopg: {
        Args: never
        Returns: Record<string, unknown>[]
      },
      hypopg_create_index: {
        Args: {
          sql_order?: string
        }
        Returns: Record<string, unknown>[]
      },
      hypopg_drop_index: {
        Args: {
          indexid?: number
        }
        Returns: boolean
      },
      hypopg_get_indexdef: {
        Args: {
          indexid?: number
        }
        Returns: string
      },
      hypopg_hidden_indexes: {
        Args: never
        Returns: number[]
      },
      hypopg_hide_index: {
        Args: {
          indexid?: number
        }
        Returns: boolean
      },
      hypopg_relation_size: {
        Args: {
          indexid?: number
        }
        Returns: number
      },
      hypopg_reset: {
        Args: never
        Returns: unknown
      },
      hypopg_reset_index: {
        Args: never
        Returns: unknown
      },
      hypopg_unhide_all_indexes: {
        Args: never
        Returns: unknown
      },
      hypopg_unhide_index: {
        Args: {
          indexid?: number
        }
        Returns: boolean
      },
      id_decode: {
        Args: {
          arg0?: string
        }
        Returns: number[]
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number[]
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: number
        }
        Returns: number[]
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: number
          arg3?: string
        }
        Returns: number[]
      },
      id_decode_once: {
        Args: {
          arg0?: string
        }
        Returns: number
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: number
        }
        Returns: number
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: number
          arg3?: string
        }
        Returns: number
      },
      id_encode: {
        Args: {
          arg0?: number
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: number
          arg1?: string
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: number
          arg1?: string
          arg2?: number
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: number
          arg1?: string
          arg2?: number
          arg3?: string
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: number[]
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: number[]
          arg1?: string
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: number[]
          arg1?: string
          arg2?: number
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: number[]
          arg1?: string
          arg2?: number
          arg3?: string
        }
        Returns: string
      },
      image_data: {
        Args: {
          id?: number
        }
        Returns: unknown
      },
      import_job_clone: {
        Args: {
          p_source_job_id?: number
          p_slug?: string
        }
        Returns: Database["public"]["Tables"]["import_job"]["Row"]
      },
      index: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: number
        }
        Returns: number
      },
      index_advisor: {
        Args: {
          query?: string
        }
        Returns: Record<string, unknown>[]
      },
      int2_dist: {
        Args: {
          arg0?: number
          arg1?: number
        }
        Returns: number
      },
      int4_dist: {
        Args: {
          arg0?: number
          arg1?: number
        }
        Returns: number
      },
      int4multirange_to_array: {
        Args: {
          p_ranges?: unknown
        }
        Returns: number[]
      },
      int8_dist: {
        Args: {
          arg0?: number
          arg1?: number
        }
        Returns: number
      },
      interval_dist: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: string
      },
      is_deriving_reports: {
        Args: never
        Returns: Json
      },
      is_deriving_statistical_units: {
        Args: never
        Returns: Json
      },
      is_importing: {
        Args: never
        Returns: Json
      },
      jsonb_stats_accum: {
        Args: {
          state?: Json
          stats?: Json
        }
        Returns: Json
      },
      jsonb_stats_accum_sfunc: {
        Args: {
          internal?: unknown
          stats?: Json
        }
        Returns: unknown
      },
      jsonb_stats_combine: {
        Args: {
          state1?: unknown
          state2?: unknown
        }
        Returns: unknown
      },
      jsonb_stats_deserial: {
        Args: {
          bytes?: string
          _internal?: unknown
        }
        Returns: unknown
      },
      jsonb_stats_final: {
        Args: {
          state?: Json
        }
        Returns: Json
      },
      jsonb_stats_final_internal: {
        Args: {
          internal?: unknown
        }
        Returns: Json
      },
      jsonb_stats_merge: {
        Args: {
          a?: Json
          b?: Json
        }
        Returns: Json
      },
      jsonb_stats_merge_sfunc: {
        Args: {
          internal?: unknown
          agg?: Json
        }
        Returns: unknown
      },
      jsonb_stats_serial: {
        Args: {
          internal?: unknown
        }
        Returns: string
      },
      jsonb_stats_sfunc: {
        Args: {
          state?: Json
          code?: string
          stat_val?: Json
        }
        Returns: Json
      },
      jsonb_stats_to_agg: {
        Args: {
          stats?: Json
        }
        Returns: Json
      },
      lca: {
        Args: {
          arg0?: string[]
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: string
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: string
          arg3?: string
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: string
          arg3?: string
          arg4?: string
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: string
          arg3?: string
          arg4?: string
          arg5?: string
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: string
          arg3?: string
          arg4?: string
          arg5?: string
          arg6?: string
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: string
          arg3?: string
          arg4?: string
          arg5?: string
          arg6?: string
          arg7?: string
        }
        Returns: string
      },
      legal_form: {
        Args: {
          statistical_unit?: Database["public"]["Tables"]["statistical_unit"]["Row"]
        }
        Returns: Database["public"]["Tables"]["legal_form"]["Row"][]
        SetofOptions: {
          from: "statistical_unit"
          to: "legal_form"
          isOneToOne: true
          isSetofReturn: true
        }
      },
      legal_form_hierarchy: {
        Args: {
          legal_form_id?: number
        }
        Returns: Json
      },
      legal_form_used_derive: {
        Args: never
        Returns: unknown
      },
      legal_unit_hierarchy: {
        Args: {
          legal_unit_id?: number
          parent_enterprise_id?: number
          scope?: Database["public"]["Enums"]["hierarchy_scope"]
          valid_on?: string
        }
        Returns: Json
      },
      list_active_sessions: {
        Args: never
        Returns: unknown[]
      },
      location_hierarchy: {
        Args: {
          parent_establishment_id?: number
          parent_legal_unit_id?: number
          valid_on?: string
        }
        Returns: Json
      },
      login: {
        Args: {
          email?: string
          password?: string
        }
        Returns: unknown
      },
      logout: {
        Args: never
        Returns: unknown
      },
      lookup_parent_and_derive_code: {
        Args: never
        Returns: unknown
      },
      lquery_in: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      lquery_out: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      lquery_recv: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      lquery_send: {
        Args: {
          arg0?: unknown
        }
        Returns: string
      },
      lt_q_regex: {
        Args: {
          arg0?: string
          arg1?: unknown[]
        }
        Returns: boolean
      },
      lt_q_rregex: {
        Args: {
          arg0?: unknown[]
          arg1?: string
        }
        Returns: boolean
      },
      ltq_regex: {
        Args: {
          arg0?: string
          arg1?: unknown
        }
        Returns: boolean
      },
      ltq_rregex: {
        Args: {
          arg0?: unknown
          arg1?: string
        }
        Returns: boolean
      },
      ltree2text: {
        Args: {
          arg0?: string
        }
        Returns: string
      },
      ltree_addltree: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: string
      },
      ltree_addtext: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: string
      },
      ltree_cmp: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number
      },
      ltree_compress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      ltree_consistent: {
        Args: {
          arg0?: unknown
          arg1?: string
          arg2?: number
          arg3?: number
          arg4?: unknown
        }
        Returns: boolean
      },
      ltree_decompress: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      ltree_eq: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      ltree_ge: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      ltree_gist_in: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      ltree_gist_options: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      ltree_gist_out: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      ltree_gt: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      ltree_in: {
        Args: {
          arg0?: unknown
        }
        Returns: string
      },
      ltree_isparent: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      ltree_le: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      ltree_lt: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      ltree_ne: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      ltree_out: {
        Args: {
          arg0?: string
        }
        Returns: unknown
      },
      ltree_penalty: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      ltree_picksplit: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      ltree_recv: {
        Args: {
          arg0?: unknown
        }
        Returns: string
      },
      ltree_risparent: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      ltree_same: {
        Args: {
          arg0?: unknown
          arg1?: unknown
          arg2?: unknown
        }
        Returns: unknown
      },
      ltree_send: {
        Args: {
          arg0?: string
        }
        Returns: string
      },
      ltree_textadd: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: string
      },
      ltree_union: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: unknown
      },
      ltreeparentsel: {
        Args: {
          arg0?: unknown
          arg1?: number
          arg2?: unknown
          arg3?: number
        }
        Returns: number
      },
      ltxtq_exec: {
        Args: {
          arg0?: string
          arg1?: unknown
        }
        Returns: boolean
      },
      ltxtq_in: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      ltxtq_out: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      ltxtq_recv: {
        Args: {
          arg0?: unknown
        }
        Returns: unknown
      },
      ltxtq_rexec: {
        Args: {
          arg0?: unknown
          arg1?: string
        }
        Returns: boolean
      },
      ltxtq_send: {
        Args: {
          arg0?: unknown
        }
        Returns: string
      },
      nlevel: {
        Args: {
          arg0?: string
        }
        Returns: number
      },
      notes_for_unit: {
        Args: {
          parent_establishment_id?: number
          parent_legal_unit_id?: number
          parent_enterprise_id?: number
          parent_enterprise_group_id?: number
        }
        Returns: Json
      },
      oid_dist: {
        Args: {
          arg0?: number
          arg1?: number
        }
        Returns: number
      },
      physical_country: {
        Args: {
          statistical_unit?: Database["public"]["Tables"]["statistical_unit"]["Row"]
        }
        Returns: Database["public"]["Tables"]["country"]["Row"][]
        SetofOptions: {
          from: "statistical_unit"
          to: "country"
          isOneToOne: true
          isSetofReturn: true
        }
      },
      physical_region: {
        Args: {
          statistical_unit?: Database["public"]["Tables"]["statistical_unit"]["Row"]
        }
        Returns: Database["public"]["Tables"]["region"]["Row"][]
        SetofOptions: {
          from: "statistical_unit"
          to: "region"
          isOneToOne: true
          isSetofReturn: true
        }
      },
      postal_country: {
        Args: {
          statistical_unit?: Database["public"]["Tables"]["statistical_unit"]["Row"]
        }
        Returns: Database["public"]["Tables"]["country"]["Row"][]
        SetofOptions: {
          from: "statistical_unit"
          to: "country"
          isOneToOne: true
          isSetofReturn: true
        }
      },
      postal_region: {
        Args: {
          statistical_unit?: Database["public"]["Tables"]["statistical_unit"]["Row"]
        }
        Returns: Database["public"]["Tables"]["region"]["Row"][]
        SetofOptions: {
          from: "statistical_unit"
          to: "region"
          isOneToOne: true
          isSetofReturn: true
        }
      },
      primary_activity_category: {
        Args: {
          statistical_unit?: Database["public"]["Tables"]["statistical_unit"]["Row"]
        }
        Returns: Database["public"]["Tables"]["activity_category"]["Row"][]
        SetofOptions: {
          from: "statistical_unit"
          to: "activity_category"
          isOneToOne: true
          isSetofReturn: true
        }
      },
      range: {
        Args: never
        Returns: string[]
      },
      recalculate_activity_category_codes: {
        Args: never
        Returns: unknown
      },
      refresh: {
        Args: never
        Returns: unknown
      },
      regexp_match: {
        Args: {
          string?: string
          pattern?: string
        }
        Returns: string[]
      }
        | {
        Args: {
          string?: string
          pattern?: string
          flags?: string
        }
        Returns: string[]
      },
      regexp_matches: {
        Args: {
          string?: string
          pattern?: string
        }
        Returns: string[][]
      }
        | {
        Args: {
          string?: string
          pattern?: string
          flags?: string
        }
        Returns: string[][]
      },
      regexp_replace: {
        Args: {
          string?: string
          pattern?: string
          replacement?: string
        }
        Returns: string
      }
        | {
        Args: {
          string?: string
          pattern?: string
          replacement?: string
          flags?: string
        }
        Returns: string
      },
      regexp_split_to_array: {
        Args: {
          string?: string
          pattern?: string
        }
        Returns: string[]
      }
        | {
        Args: {
          string?: string
          pattern?: string
          flags?: string
        }
        Returns: string[]
      },
      regexp_split_to_table: {
        Args: {
          string?: string
          pattern?: string
        }
        Returns: string[]
      }
        | {
        Args: {
          string?: string
          pattern?: string
          flags?: string
        }
        Returns: string[]
      },
      region_hierarchy: {
        Args: {
          region_id?: number
        }
        Returns: Json
      },
      region_used_derive: {
        Args: never
        Returns: unknown
      },
      relevant_statistical_units: {
        Args: {
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          unit_id?: number
          valid_on?: string
        }
        Returns: Database["public"]["Tables"]["statistical_unit"]["Row"][]
      },
      remove_ephemeral_data_from_hierarchy: {
        Args: {
          data?: Json
        }
        Returns: Json
      },
      replace: {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: string
        }
        Returns: string
      },
      report_partition_seq: {
        Args: {
          p_unit_type?: string
          p_unit_id?: number
          p_num_partitions?: number
        }
        Returns: number
      }
        | {
        Args: {
          p_unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          p_unit_id?: number
          p_num_partitions?: number
        }
        Returns: number
      },
      reset: {
        Args: {
          confirmed?: boolean
          scope?: Database["public"]["Enums"]["reset_scope"]
        }
        Returns: Json
      },
      revoke_api_key: {
        Args: {
          key_jti?: string
        }
        Returns: boolean
      },
      revoke_session: {
        Args: {
          refresh_session_jti?: string
        }
        Returns: boolean
      },
      secondary_activity_category: {
        Args: {
          statistical_unit?: Database["public"]["Tables"]["statistical_unit"]["Row"]
        }
        Returns: Database["public"]["Tables"]["activity_category"]["Row"][]
        SetofOptions: {
          from: "statistical_unit"
          to: "activity_category"
          isOneToOne: true
          isSetofReturn: true
        }
      },
      sector: {
        Args: {
          statistical_unit?: Database["public"]["Tables"]["statistical_unit"]["Row"]
        }
        Returns: Database["public"]["Tables"]["sector"]["Row"][]
        SetofOptions: {
          from: "statistical_unit"
          to: "sector"
          isOneToOne: true
          isSetofReturn: true
        }
      },
      sector_hierarchy: {
        Args: {
          sector_id?: number
        }
        Returns: Json
      },
      sector_used_derive: {
        Args: never
        Returns: unknown
      },
      set_limit: {
        Args: {
          arg0?: number
        }
        Returns: number
      },
      set_primary_establishment_for_legal_unit: {
        Args: {
          establishment_id?: number
          valid_from_param?: string
          valid_to_param?: string
        }
        Returns: Json
      },
      set_primary_legal_unit_for_enterprise: {
        Args: {
          legal_unit_id?: number
          valid_from_param?: string
          valid_to_param?: string
        }
        Returns: Json
      },
      set_report_partition_seq: {
        Args: never
        Returns: unknown
      },
      show_limit: {
        Args: never
        Returns: number
      },
      show_trgm: {
        Args: {
          arg0?: string
        }
        Returns: string[]
      },
      similarity: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number
      },
      similarity_dist: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number
      },
      similarity_op: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      split_part: {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: number
        }
        Returns: string
      },
      stat: {
        Args: {
          value?: unknown
        }
        Returns: Json
      },
      stat_for_unit_hierarchy: {
        Args: {
          parent_establishment_id?: number
          parent_legal_unit_id?: number
          valid_on?: string
        }
        Returns: Json
      },
      statistical_history_def: {
        Args: {
          p_resolution?: Database["public"]["Enums"]["history_resolution"]
          p_year?: number
          p_month?: number
          p_partition_seq?: number
        }
        Returns: Database["public"]["CompositeTypes"]["statistical_history_type"][]
      },
      statistical_history_derive: {
        Args: {
          p_valid_from?: string
          p_valid_until?: string
        }
        Returns: unknown
      },
      statistical_history_drilldown: {
        Args: {
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          resolution?: Database["public"]["Enums"]["history_resolution"]
          year?: number
          region_path?: string
          activity_category_path?: string
          sector_path?: string
          status_id?: number
          legal_form_id?: number
          country_id?: number
          year_min?: number
          year_max?: number
        }
        Returns: Json
      },
      statistical_history_facet_def: {
        Args: {
          p_resolution?: Database["public"]["Enums"]["history_resolution"]
          p_year?: number
          p_month?: number
          p_partition_seq?: number
        }
        Returns: Database["public"]["CompositeTypes"]["statistical_history_facet_type"][]
      },
      statistical_history_facet_derive: {
        Args: {
          p_valid_from?: string
          p_valid_until?: string
        }
        Returns: unknown
      },
      statistical_history_highcharts: {
        Args: {
          p_resolution?: Database["public"]["Enums"]["history_resolution"]
          p_unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          p_year?: number
          p_series_codes?: string[]
        }
        Returns: Json
      },
      statistical_unit_details: {
        Args: {
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          unit_id?: number
          valid_on?: string
        }
        Returns: Json
      },
      statistical_unit_enterprise_id: {
        Args: {
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          unit_id?: number
          valid_on?: string
        }
        Returns: number
      },
      statistical_unit_facet_derive: {
        Args: {
          p_valid_from?: string
          p_valid_until?: string
        }
        Returns: unknown
      },
      statistical_unit_facet_drilldown: {
        Args: {
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          region_path?: string
          activity_category_path?: string
          sector_path?: string
          status_id?: number
          legal_form_id?: number
          country_id?: number
          valid_on?: string
        }
        Returns: Json
      },
      statistical_unit_hierarchy: {
        Args: {
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          unit_id?: number
          scope?: Database["public"]["Enums"]["hierarchy_scope"]
          valid_on?: string
          strip_nulls?: boolean
        }
        Returns: Json
      },
      statistical_unit_history_highcharts: {
        Args: {
          p_unit_id?: number
          p_unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
        }
        Returns: Json
      },
      statistical_unit_stats: {
        Args: {
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          unit_id?: number
          valid_on?: string
        }
        Returns: Database["public"]["CompositeTypes"]["statistical_unit_stats"][]
      },
      statistical_unit_tree: {
        Args: {
          unit_type?: Database["public"]["Enums"]["statistical_unit_type"]
          unit_id?: number
          valid_on?: string
        }
        Returns: Json
      },
      stats: {
        Args: {
          input?: Json
        }
        Returns: Json
      }
        | {
        Args: {
          code?: string
          val?: unknown
        }
        Returns: Json
      },
      status: {
        Args: {
          statistical_unit?: Database["public"]["Tables"]["statistical_unit"]["Row"]
        }
        Returns: Database["public"]["Tables"]["status"]["Row"][]
        SetofOptions: {
          from: "statistical_unit"
          to: "status"
          isOneToOne: true
          isSetofReturn: true
        }
      },
      status_hierarchy: {
        Args: {
          status_id?: number
        }
        Returns: Json
      },
      strict_word_similarity: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number
      },
      strict_word_similarity_commutator_op: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      strict_word_similarity_dist_commutator_op: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number
      },
      strict_word_similarity_dist_op: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number
      },
      strict_word_similarity_op: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      strpos: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number
      },
      subltree: {
        Args: {
          arg0?: string
          arg1?: number
          arg2?: number
        }
        Returns: string
      },
      subpath: {
        Args: {
          arg0?: string
          arg1?: number
          arg2?: number
        }
        Returns: string
      }
        | {
        Args: {
          arg0?: string
          arg1?: number
        }
        Returns: string
      },
      tag_for_unit_hierarchy: {
        Args: {
          parent_establishment_id?: number
          parent_legal_unit_id?: number
          parent_enterprise_id?: number
          parent_enterprise_group_id?: number
        }
        Returns: Json
      },
      text_to_bytea: {
        Args: {
          data?: string
        }
        Returns: string
      },
      texticlike: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      texticnlike: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      texticregexeq: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      texticregexne: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      }
        | {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      time_dist: {
        Args: {
          arg0?: unknown
          arg1?: unknown
        }
        Returns: string
      },
      timepoints_calculate: {
        Args: {
          p_establishment_id_ranges?: unknown
          p_legal_unit_id_ranges?: unknown
          p_enterprise_id_ranges?: unknown
        }
        Returns: Record<string, unknown>[]
      },
      translate: {
        Args: {
          arg0?: string
          arg1?: string
          arg2?: string
        }
        Returns: string
      },
      ts_dist: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: string
      },
      tstz_dist: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: string
      },
      unit_size: {
        Args: {
          statistical_unit?: Database["public"]["Tables"]["statistical_unit"]["Row"]
        }
        Returns: Database["public"]["Tables"]["unit_size"]["Row"][]
        SetofOptions: {
          from: "statistical_unit"
          to: "unit_size"
          isOneToOne: true
          isSetofReturn: true
        }
      },
      unit_size_hierarchy: {
        Args: {
          unit_size_id?: number
        }
        Returns: Json
      },
      urlencode: {
        Args: {
          string?: string
        }
        Returns: string
      }
        | {
        Args: {
          string?: string
        }
        Returns: string
      }
        | {
        Args: {
          data?: Json
        }
        Returns: string
      },
      user_create: {
        Args: {
          p_display_name?: string
          p_email?: string
          p_statbus_role?: Database["public"]["Enums"]["statbus_role"]
          p_password?: string
        }
        Returns: Record<string, unknown>[]
      },
      validate_image_on_insert: {
        Args: never
        Returns: unknown
      },
      websearch_to_wildcard_tsquery: {
        Args: {
          query?: string
        }
        Returns: unknown
      },
      word_similarity: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number
      },
      word_similarity_commutator_op: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      },
      word_similarity_dist_commutator_op: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number
      },
      word_similarity_dist_op: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: number
      },
      word_similarity_op: {
        Args: {
          arg0?: string
          arg1?: string
        }
        Returns: boolean
      }
    },
    Enums: {
      activity_category_code_behaviour: "digits" | "dot_after_two_digits",
      activity_type: "primary" | "secondary" | "ancilliary",
      allen_interval_relation: 
          | "precedes"
          | "meets"
          | "overlaps"
          | "starts"
          | "during"
          | "finishes"
          | "equals"
          | "overlapped_by"
          | "started_by"
          | "contains"
          | "finished_by"
          | "met_by"
          | "preceded_by",
      external_ident_shape: "regular" | "hierarchical",
      hierarchy_scope: "all" | "tree" | "details",
      history_resolution: "year" | "year-month",
      import_data_column_purpose: 
          | "source_input"
          | "internal"
          | "pk_id"
          | "metadata",
      import_data_state: 
          | "pending"
          | "analysing"
          | "analysed"
          | "processing"
          | "processed"
          | "error",
      import_job_state: 
          | "waiting_for_upload"
          | "upload_completed"
          | "preparing_data"
          | "analysing_data"
          | "waiting_for_review"
          | "approved"
          | "rejected"
          | "processing_data"
          | "failed"
          | "finished",
      import_mode: 
          | "legal_unit"
          | "establishment_formal"
          | "establishment_informal"
          | "generic_unit",
      import_row_action_type: "use" | "skip",
      import_row_operation_type: "insert" | "replace" | "update",
      import_source_expression: "now" | "default",
      import_step_phase: "analyse" | "process",
      import_strategy: 
          | "insert_or_replace"
          | "insert_only"
          | "replace_only"
          | "insert_or_update"
          | "update_only",
      import_valid_time_from: "job_provided" | "source_columns",
      location_type: "physical" | "postal",
      person_sex: "Male" | "Female",
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
          | "start_of_decade_prev",
      relative_period_scope: "input_and_query" | "query" | "input",
      reset_scope: "units" | "data" | "getting-started" | "all",
      stat_frequency: 
          | "daily"
          | "weekly"
          | "biweekly"
          | "monthly"
          | "bimonthly"
          | "quarterly"
          | "semesterly"
          | "yearly",
      stat_type: "int" | "float" | "string" | "bool",
      statbus_role: 
          | "admin_user"
          | "regular_user"
          | "restricted_user"
          | "external_user",
      statistical_unit_type: 
          | "establishment"
          | "legal_unit"
          | "enterprise"
          | "enterprise_group",
      tag_type: "custom" | "system",
      time_context_type: "relative_period" | "tag" | "year"
    },
    CompositeTypes: {
      http_header: {
        field: string | null
        value: string | null
      },
      http_request: {
        method: unknown | null
        uri: string | null
        headers: Database["public"]["CompositeTypes"]["http_header"][] | null
        content_type: string | null
        content: string | null
      },
      http_response: {
        status: number | null
        content_type: string | null
        headers: Database["public"]["CompositeTypes"]["http_header"][] | null
        content: string | null
      },
      statistical_history_facet_type: {
        resolution: Database["public"]["Enums"]["history_resolution"] | null
        year: number | null
        month: number | null
        unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
        primary_activity_category_path: string | null
        secondary_activity_category_path: string | null
        sector_path: string | null
        legal_form_id: number | null
        physical_region_path: string | null
        physical_country_id: number | null
        unit_size_id: number | null
        status_id: number | null
        exists_count: number | null
        exists_change: number | null
        exists_added_count: number | null
        exists_removed_count: number | null
        countable_count: number | null
        countable_change: number | null
        countable_added_count: number | null
        countable_removed_count: number | null
        births: number | null
        deaths: number | null
        name_change_count: number | null
        primary_activity_category_change_count: number | null
        secondary_activity_category_change_count: number | null
        sector_change_count: number | null
        legal_form_change_count: number | null
        physical_region_change_count: number | null
        physical_country_change_count: number | null
        physical_address_change_count: number | null
        unit_size_change_count: number | null
        status_change_count: number | null
        stats_summary: Json | null
      },
      statistical_history_type: {
        resolution: Database["public"]["Enums"]["history_resolution"] | null
        year: number | null
        month: number | null
        unit_type: Database["public"]["Enums"]["statistical_unit_type"] | null
        exists_count: number | null
        exists_change: number | null
        exists_added_count: number | null
        exists_removed_count: number | null
        countable_count: number | null
        countable_change: number | null
        countable_added_count: number | null
        countable_removed_count: number | null
        births: number | null
        deaths: number | null
        name_change_count: number | null
        primary_activity_category_change_count: number | null
        secondary_activity_category_change_count: number | null
        sector_change_count: number | null
        legal_form_change_count: number | null
        physical_region_change_count: number | null
        physical_country_change_count: number | null
        physical_address_change_count: number | null
        stats_summary: Json | null
        partition_seq: number | null
      },
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
  EnumName extends PublicEnumNameOrOptions extends {
    schema: keyof Database
  }
    ? keyof Database[PublicEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = PublicEnumNameOrOptions extends {
  schema: keyof Database
}
  ? Database[PublicEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : PublicEnumNameOrOptions extends keyof PublicSchema["Enums"]
    ? PublicSchema["Enums"][PublicEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof PublicSchema["CompositeTypes"]
    | { schema: keyof Database },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof Database
  }
    ? keyof Database[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof Database
}
  ? Database[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof PublicSchema["CompositeTypes"]
    ? PublicSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      activity_category_code_behaviour: ["digits", "dot_after_two_digits"],
      activity_type: ["primary", "secondary", "ancilliary"],
      allen_interval_relation: [
        "precedes",
        "meets",
        "overlaps",
        "starts",
        "during",
        "finishes",
        "equals",
        "overlapped_by",
        "started_by",
        "contains",
        "finished_by",
        "met_by",
        "preceded_by"
      ],
      external_ident_shape: ["regular", "hierarchical"],
      hierarchy_scope: ["all", "tree", "details"],
      history_resolution: ["year", "year-month"],
      import_data_column_purpose: [
        "source_input",
        "internal",
        "pk_id",
        "metadata"
      ],
      import_data_state: [
        "pending",
        "analysing",
        "analysed",
        "processing",
        "processed",
        "error"
      ],
      import_job_state: [
        "waiting_for_upload",
        "upload_completed",
        "preparing_data",
        "analysing_data",
        "waiting_for_review",
        "approved",
        "rejected",
        "processing_data",
        "failed",
        "finished"
      ],
      import_mode: [
        "legal_unit",
        "establishment_formal",
        "establishment_informal",
        "generic_unit"
      ],
      import_row_action_type: ["use", "skip"],
      import_row_operation_type: ["insert", "replace", "update"],
      import_source_expression: ["now", "default"],
      import_step_phase: ["analyse", "process"],
      import_strategy: [
        "insert_or_replace",
        "insert_only",
        "replace_only",
        "insert_or_update",
        "update_only"
      ],
      import_valid_time_from: ["job_provided", "source_columns"],
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
        "start_of_decade_prev"
      ],
      relative_period_scope: ["input_and_query", "query", "input"],
      reset_scope: ["units", "data", "getting-started", "all"],
      stat_frequency: [
        "daily",
        "weekly",
        "biweekly",
        "monthly",
        "bimonthly",
        "quarterly",
        "semesterly",
        "yearly"
      ],
      stat_type: ["int", "float", "string", "bool"],
      statbus_role: [
        "admin_user",
        "regular_user",
        "restricted_user",
        "external_user"
      ],
      statistical_unit_type: [
        "establishment",
        "legal_unit",
        "enterprise",
        "enterprise_group"
      ],
      tag_type: ["custom", "system"],
      time_context_type: ["relative_period", "tag", "year"]
    }
  }
} as const

