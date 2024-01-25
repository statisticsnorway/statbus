export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export interface Database {
  public: {
    Tables: {
      activity: {
        Row: {
          activity_category_id: number
          activity_type: Database["public"]["Enums"]["activity_type"]
          establishment_id: number | null
          id: number
          legal_unit_id: number | null
          updated_at: string
          updated_by_user_id: number
          valid_from: string
          valid_to: string
        }
        Insert: {
          activity_category_id: number
          activity_type: Database["public"]["Enums"]["activity_type"]
          establishment_id?: number | null
          id?: number
          legal_unit_id?: number | null
          updated_at?: string
          updated_by_user_id: number
          valid_from?: string
          valid_to?: string
        }
        Update: {
          activity_category_id?: number
          activity_type?: Database["public"]["Enums"]["activity_type"]
          establishment_id?: number | null
          id?: number
          legal_unit_id?: number | null
          updated_at?: string
          updated_by_user_id?: number
          valid_from?: string
          valid_to?: string
        }
        Relationships: [
          {
            foreignKeyName: "activity_activity_category_id_fkey"
            columns: ["activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_activity_category_id_fkey"
            columns: ["activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_updated_by_user_id_fkey"
            columns: ["updated_by_user_id"]
            isOneToOne: false
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          }
        ]
      }
      activity_category: {
        Row: {
          active: boolean
          activity_category_standard_id: number
          code: string | null
          custom: boolean
          description: string | null
          id: number
          label: string
          level: number | null
          name: string
          parent_id: number | null
          path: unknown
          updated_at: string
        }
        Insert: {
          active: boolean
          activity_category_standard_id: number
          code?: string | null
          custom: boolean
          description?: string | null
          id?: number
          label?: string
          level?: number | null
          name: string
          parent_id?: number | null
          path: unknown
          updated_at?: string
        }
        Update: {
          active?: boolean
          activity_category_standard_id?: number
          code?: string | null
          custom?: boolean
          description?: string | null
          id?: number
          label?: string
          level?: number | null
          name?: string
          parent_id?: number | null
          path?: unknown
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "activity_category_activity_category_standard_id_fkey"
            columns: ["activity_category_standard_id"]
            isOneToOne: false
            referencedRelation: "activity_category_standard"
            referencedColumns: ["id"]
          },
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
            foreignKeyName: "fk_activity_category_activity_category_parent_id"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_activity_category_activity_category_parent_id"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "activity_category_available"
            referencedColumns: ["id"]
          }
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
          id?: number
          role_id: number
        }
        Update: {
          activity_category_id?: number
          id?: number
          role_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "fk_activity_category_role_activity_category_activity_category_"
            columns: ["activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_activity_category_role_activity_category_activity_category_"
            columns: ["activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_activity_category_role_role_role_id"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "statbus_role"
            referencedColumns: ["id"]
          }
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
          id?: number
          name: string
          obsolete?: boolean
        }
        Update: {
          code?: string
          id?: number
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
          id?: number
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
          id?: number
          issued_at?: string
          legal_unit_id?: number | null
          resolved_at?: string | null
          summary_messages?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_analysis_log_analysis_queue_analysis_queue_id"
            columns: ["analysis_queue_id"]
            isOneToOne: false
            referencedRelation: "analysis_queue"
            referencedColumns: ["id"]
          }
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
          id?: number
          server_end_period?: string | null
          server_start_period?: string | null
          user_end_period: string
          user_id: number
          user_start_period: string
        }
        Update: {
          comment?: string | null
          id?: number
          server_end_period?: string | null
          server_start_period?: string | null
          user_end_period?: string
          user_id?: number
          user_start_period?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_analysis_queue_user_user_id"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          }
        ]
      }
      country: {
        Row: {
          active: boolean
          code_2: string
          code_3: string
          code_num: string
          custom: boolean
          id: number
          name: string
          updated_at: string
        }
        Insert: {
          active: boolean
          code_2: string
          code_3: string
          code_num: string
          custom: boolean
          id?: never
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code_2?: string
          code_3?: string
          code_num?: string
          custom?: boolean
          id?: never
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      country_for_unit: {
        Row: {
          country_id: number
          enterprise_group_id: number | null
          enterprise_id: number | null
          establishment_id: number | null
          id: number
          legal_unit_id: number | null
        }
        Insert: {
          country_id: number
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: number
          legal_unit_id?: number | null
        }
        Update: {
          country_id?: number
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: number
          legal_unit_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "country_for_unit_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "country_for_unit_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "country_view"
            referencedColumns: ["id"]
          }
        ]
      }
      custom_analysis_check: {
        Row: {
          id: number
          name: string | null
          query: string | null
          target_unit_types: string | null
        }
        Insert: {
          id?: number
          name?: string | null
          query?: string | null
          target_unit_types?: string | null
        }
        Update: {
          id?: number
          name?: string | null
          query?: string | null
          target_unit_types?: string | null
        }
        Relationships: []
      }
      custom_view_def: {
        Row: {
          created_at: string
          id: number
          name: string
          note: string | null
          slug: string
          target_table_id: number | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: number
          name: string
          note?: string | null
          slug: string
          target_table_id?: number | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: number
          name?: string
          note?: string | null
          slug?: string
          target_table_id?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "custom_view_def_target_table_id_fkey"
            columns: ["target_table_id"]
            isOneToOne: false
            referencedRelation: "custom_view_def_target_table"
            referencedColumns: ["id"]
          }
        ]
      }
      custom_view_def_mapping: {
        Row: {
          created_at: string
          custom_view_def_id: number | null
          source_column_id: number | null
          target_column_id: number | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          custom_view_def_id?: number | null
          source_column_id?: number | null
          target_column_id?: number | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          custom_view_def_id?: number | null
          source_column_id?: number | null
          target_column_id?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "custom_view_def_mapping_custom_view_def_id_fkey"
            columns: ["custom_view_def_id"]
            isOneToOne: false
            referencedRelation: "custom_view_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_view_def_mapping_custom_view_def_id_fkey"
            columns: ["custom_view_def_id"]
            isOneToOne: false
            referencedRelation: "custom_view_def_expanded"
            referencedColumns: ["view_def_id"]
          },
          {
            foreignKeyName: "custom_view_def_mapping_source_column_id_fkey"
            columns: ["source_column_id"]
            isOneToOne: false
            referencedRelation: "custom_view_def_source_column"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_view_def_mapping_target_column_id_fkey"
            columns: ["target_column_id"]
            isOneToOne: false
            referencedRelation: "custom_view_def_target_column"
            referencedColumns: ["id"]
          }
        ]
      }
      custom_view_def_source_column: {
        Row: {
          column_name: string
          created_at: string
          custom_view_def_id: number | null
          id: number
          priority: number
          updated_at: string
        }
        Insert: {
          column_name: string
          created_at?: string
          custom_view_def_id?: number | null
          id?: number
          priority: number
          updated_at?: string
        }
        Update: {
          column_name?: string
          created_at?: string
          custom_view_def_id?: number | null
          id?: number
          priority?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "custom_view_def_source_column_custom_view_def_id_fkey"
            columns: ["custom_view_def_id"]
            isOneToOne: false
            referencedRelation: "custom_view_def"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_view_def_source_column_custom_view_def_id_fkey"
            columns: ["custom_view_def_id"]
            isOneToOne: false
            referencedRelation: "custom_view_def_expanded"
            referencedColumns: ["view_def_id"]
          }
        ]
      }
      custom_view_def_target_column: {
        Row: {
          column_name: string
          created_at: string
          id: number
          target_table_id: number | null
          uniquely_identifying: boolean
          updated_at: string
        }
        Insert: {
          column_name: string
          created_at?: string
          id?: number
          target_table_id?: number | null
          uniquely_identifying: boolean
          updated_at?: string
        }
        Update: {
          column_name?: string
          created_at?: string
          id?: number
          target_table_id?: number | null
          uniquely_identifying?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "custom_view_def_target_column_target_table_id_fkey"
            columns: ["target_table_id"]
            isOneToOne: false
            referencedRelation: "custom_view_def_target_table"
            referencedColumns: ["id"]
          }
        ]
      }
      custom_view_def_target_table: {
        Row: {
          created_at: string
          id: number
          name: string
          schema_name: string
          table_name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: number
          name: string
          schema_name: string
          table_name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: number
          name?: string
          schema_name?: string
          table_name?: string
          updated_at?: string
        }
        Relationships: []
      }
      data_source: {
        Row: {
          allowed_operations: Database["public"]["Enums"]["allowed_operations"]
          attributes_to_check: string | null
          csv_delimiter: string | null
          csv_skip_count: number
          data_source_upload_type: Database["public"]["Enums"]["data_source_upload_type"]
          description: string | null
          id: number
          name: string
          original_csv_attributes: string | null
          priority: Database["public"]["Enums"]["data_source_priority"]
          restrictions: string | null
          stat_unit_type: Database["public"]["Enums"]["stat_unit_type"]
          user_id: number | null
          variables_mapping: string | null
        }
        Insert: {
          allowed_operations: Database["public"]["Enums"]["allowed_operations"]
          attributes_to_check?: string | null
          csv_delimiter?: string | null
          csv_skip_count: number
          data_source_upload_type: Database["public"]["Enums"]["data_source_upload_type"]
          description?: string | null
          id?: number
          name: string
          original_csv_attributes?: string | null
          priority: Database["public"]["Enums"]["data_source_priority"]
          restrictions?: string | null
          stat_unit_type: Database["public"]["Enums"]["stat_unit_type"]
          user_id?: number | null
          variables_mapping?: string | null
        }
        Update: {
          allowed_operations?: Database["public"]["Enums"]["allowed_operations"]
          attributes_to_check?: string | null
          csv_delimiter?: string | null
          csv_skip_count?: number
          data_source_upload_type?: Database["public"]["Enums"]["data_source_upload_type"]
          description?: string | null
          id?: number
          name?: string
          original_csv_attributes?: string | null
          priority?: Database["public"]["Enums"]["data_source_priority"]
          restrictions?: string | null
          stat_unit_type?: Database["public"]["Enums"]["stat_unit_type"]
          user_id?: number | null
          variables_mapping?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_data_source_user_user_id"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          }
        ]
      }
      data_source_classification: {
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
          id?: number
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          custom?: boolean
          id?: number
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      data_source_queue: {
        Row: {
          data_source_file_name: string
          data_source_id: number
          data_source_path: string
          description: string | null
          end_import_date: string | null
          id: number
          note: string | null
          skip_lines_count: number
          start_import_date: string | null
          status: number
          user_id: number | null
        }
        Insert: {
          data_source_file_name: string
          data_source_id: number
          data_source_path: string
          description?: string | null
          end_import_date?: string | null
          id?: number
          note?: string | null
          skip_lines_count: number
          start_import_date?: string | null
          status: number
          user_id?: number | null
        }
        Update: {
          data_source_file_name?: string
          data_source_id?: number
          data_source_path?: string
          description?: string | null
          end_import_date?: string | null
          id?: number
          note?: string | null
          skip_lines_count?: number
          start_import_date?: string | null
          status?: number
          user_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_data_source_queue_data_source_data_source_id"
            columns: ["data_source_id"]
            isOneToOne: false
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_data_source_queue_user_user_id"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          }
        ]
      }
      data_uploading_log: {
        Row: {
          data_source_queue_id: number
          end_import_date: string | null
          errors: string | null
          id: number
          note: string | null
          serialized_raw_unit: string | null
          serialized_unit: string | null
          start_import_date: string | null
          stat_unit_name: string | null
          status: number
          summary: string | null
          target_stat_ident: string | null
        }
        Insert: {
          data_source_queue_id: number
          end_import_date?: string | null
          errors?: string | null
          id?: number
          note?: string | null
          serialized_raw_unit?: string | null
          serialized_unit?: string | null
          start_import_date?: string | null
          stat_unit_name?: string | null
          status: number
          summary?: string | null
          target_stat_ident?: string | null
        }
        Update: {
          data_source_queue_id?: number
          end_import_date?: string | null
          errors?: string | null
          id?: number
          note?: string | null
          serialized_raw_unit?: string | null
          serialized_unit?: string | null
          start_import_date?: string | null
          stat_unit_name?: string | null
          status?: number
          summary?: string | null
          target_stat_ident?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_data_uploading_log_data_source_queue_data_source_queue_id"
            columns: ["data_source_queue_id"]
            isOneToOne: false
            referencedRelation: "data_source_queue"
            referencedColumns: ["id"]
          }
        ]
      }
      enterprise: {
        Row: {
          active: boolean
          created_at: string
          data_source_classification_id: number | null
          edit_by_user_id: string
          edit_comment: string | null
          email_address: string | null
          enterprise_group_date: string | null
          enterprise_group_id: number | null
          enterprise_group_role_id: number | null
          external_ident: string | null
          external_ident_date: string | null
          external_ident_type: string | null
          foreign_participation_id: number | null
          id: number
          name: string | null
          notes: string | null
          parent_org_link: number | null
          sector_code_id: number | null
          short_name: string | null
          stat_ident: string | null
          stat_ident_date: string | null
          telephone_no: string | null
          unit_size_id: number | null
          valid_from: string
          valid_to: string
          web_address: string | null
        }
        Insert: {
          active?: boolean
          created_at?: string
          data_source_classification_id?: number | null
          edit_by_user_id: string
          edit_comment?: string | null
          email_address?: string | null
          enterprise_group_date?: string | null
          enterprise_group_id?: number | null
          enterprise_group_role_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          id?: number
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          sector_code_id?: number | null
          short_name?: string | null
          stat_ident?: string | null
          stat_ident_date?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_from?: string
          valid_to?: string
          web_address?: string | null
        }
        Update: {
          active?: boolean
          created_at?: string
          data_source_classification_id?: number | null
          edit_by_user_id?: string
          edit_comment?: string | null
          email_address?: string | null
          enterprise_group_date?: string | null
          enterprise_group_id?: number | null
          enterprise_group_role_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          id?: number
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          sector_code_id?: number | null
          short_name?: string | null
          stat_ident?: string | null
          stat_ident_date?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_from?: string
          valid_to?: string
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_enterprise_data_source_classification_data_source_clas"
            columns: ["data_source_classification_id"]
            isOneToOne: false
            referencedRelation: "data_source_classification"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_data_source_classification_data_source_clas"
            columns: ["data_source_classification_id"]
            isOneToOne: false
            referencedRelation: "data_source_classification_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_data_source_classification_data_source_clas"
            columns: ["data_source_classification_id"]
            isOneToOne: false
            referencedRelation: "data_source_classification_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_enterprise_group_role_enterprise_group_role_id"
            columns: ["enterprise_group_role_id"]
            isOneToOne: false
            referencedRelation: "enterprise_group_role"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_enterprise_group_role_enterprise_group_role_id"
            columns: ["enterprise_group_role_id"]
            isOneToOne: false
            referencedRelation: "enterprise_group_role_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_enterprise_group_role_enterprise_group_role_id"
            columns: ["enterprise_group_role_id"]
            isOneToOne: false
            referencedRelation: "enterprise_group_role_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_foreign_participation_foreign_participation"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_foreign_participation_foreign_participation"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_foreign_participation_foreign_participation"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_sector_code_sector_code_id"
            columns: ["sector_code_id"]
            isOneToOne: false
            referencedRelation: "sector_code"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_sector_code_sector_code_id"
            columns: ["sector_code_id"]
            isOneToOne: false
            referencedRelation: "sector_code_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_sector_code_sector_code_id"
            columns: ["sector_code_id"]
            isOneToOne: false
            referencedRelation: "sector_code_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_unit_size_size_id"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_unit_size_size_id"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_unit_size_size_id"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_system"
            referencedColumns: ["id"]
          }
        ]
      }
      enterprise_group: {
        Row: {
          active: boolean
          contact_person: string | null
          created_at: string
          data_source: string | null
          data_source_classification_id: number | null
          edit_by_user_id: number
          edit_comment: string | null
          email_address: string | null
          enterprise_group_type_id: number | null
          external_ident: string | null
          external_ident_date: string | null
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
          stat_ident_date: string | null
          telephone_no: string | null
          unit_size_id: number | null
          valid_from: string
          valid_to: string
          web_address: string | null
        }
        Insert: {
          active?: boolean
          contact_person?: string | null
          created_at?: string
          data_source?: string | null
          data_source_classification_id?: number | null
          edit_by_user_id: number
          edit_comment?: string | null
          email_address?: string | null
          enterprise_group_type_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
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
          stat_ident_date?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_from?: string
          valid_to?: string
          web_address?: string | null
        }
        Update: {
          active?: boolean
          contact_person?: string | null
          created_at?: string
          data_source?: string | null
          data_source_classification_id?: number | null
          edit_by_user_id?: number
          edit_comment?: string | null
          email_address?: string | null
          enterprise_group_type_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
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
          stat_ident_date?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_from?: string
          valid_to?: string
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_enterprise_group_data_source_classification_data_source_cla"
            columns: ["data_source_classification_id"]
            isOneToOne: false
            referencedRelation: "data_source_classification"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_data_source_classification_data_source_cla"
            columns: ["data_source_classification_id"]
            isOneToOne: false
            referencedRelation: "data_source_classification_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_data_source_classification_data_source_cla"
            columns: ["data_source_classification_id"]
            isOneToOne: false
            referencedRelation: "data_source_classification_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_enterprise_group_type_enterprise_group_type"
            columns: ["enterprise_group_type_id"]
            isOneToOne: false
            referencedRelation: "enterprise_group_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_enterprise_group_type_enterprise_group_type"
            columns: ["enterprise_group_type_id"]
            isOneToOne: false
            referencedRelation: "enterprise_group_type_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_enterprise_group_type_enterprise_group_type"
            columns: ["enterprise_group_type_id"]
            isOneToOne: false
            referencedRelation: "enterprise_group_type_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_foreign_participation_foreign_participatio"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_foreign_participation_foreign_participatio"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_foreign_participation_foreign_participatio"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_unit_size_size_id"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_unit_size_size_id"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_unit_size_size_id"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_system"
            referencedColumns: ["id"]
          }
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
          id?: number
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          custom?: boolean
          id?: number
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
          id?: number
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          custom?: boolean
          id?: number
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      establishment: {
        Row: {
          active: boolean
          birth_date: string | null
          data_source: string | null
          data_source_classification_id: number | null
          death_date: string | null
          edit_by_user_id: string
          edit_comment: string
          email_address: string | null
          enterprise_id: number | null
          external_ident: string | null
          external_ident_date: string | null
          external_ident_type: string | null
          free_econ_zone: boolean | null
          id: number
          name: string | null
          notes: string | null
          parent_org_link: number | null
          reorg_date: string | null
          reorg_references: number | null
          reorg_type_id: number | null
          sector_code_id: number | null
          seen_in_import_at: string | null
          short_name: string | null
          stat_ident: string | null
          stat_ident_date: string | null
          tax_reg_date: string | null
          tax_reg_ident: string | null
          telephone_no: string | null
          unit_size_id: number | null
          valid_from: string
          valid_to: string
          web_address: string | null
        }
        Insert: {
          active?: boolean
          birth_date?: string | null
          data_source?: string | null
          data_source_classification_id?: number | null
          death_date?: string | null
          edit_by_user_id: string
          edit_comment: string
          email_address?: string | null
          enterprise_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          free_econ_zone?: boolean | null
          id?: number
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_id?: number | null
          sector_code_id?: number | null
          seen_in_import_at?: string | null
          short_name?: string | null
          stat_ident?: string | null
          stat_ident_date?: string | null
          tax_reg_date?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_from?: string
          valid_to?: string
          web_address?: string | null
        }
        Update: {
          active?: boolean
          birth_date?: string | null
          data_source?: string | null
          data_source_classification_id?: number | null
          death_date?: string | null
          edit_by_user_id?: string
          edit_comment?: string
          email_address?: string | null
          enterprise_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          free_econ_zone?: boolean | null
          id?: number
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_id?: number | null
          sector_code_id?: number | null
          seen_in_import_at?: string | null
          short_name?: string | null
          stat_ident?: string | null
          stat_ident_date?: string | null
          tax_reg_date?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_from?: string
          valid_to?: string
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_establishment_data_source_classification_data_source_classif"
            columns: ["data_source_classification_id"]
            isOneToOne: false
            referencedRelation: "data_source_classification"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_establishment_data_source_classification_data_source_classif"
            columns: ["data_source_classification_id"]
            isOneToOne: false
            referencedRelation: "data_source_classification_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_establishment_data_source_classification_data_source_classif"
            columns: ["data_source_classification_id"]
            isOneToOne: false
            referencedRelation: "data_source_classification_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_establishment_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_establishment_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_establishment_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_establishment_sector_code_sector_code_id"
            columns: ["sector_code_id"]
            isOneToOne: false
            referencedRelation: "sector_code"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_establishment_sector_code_sector_code_id"
            columns: ["sector_code_id"]
            isOneToOne: false
            referencedRelation: "sector_code_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_establishment_sector_code_sector_code_id"
            columns: ["sector_code_id"]
            isOneToOne: false
            referencedRelation: "sector_code_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_establishment_unit_size_size_id"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_establishment_unit_size_size_id"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_establishment_unit_size_size_id"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_system"
            referencedColumns: ["id"]
          }
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
          id?: number
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          custom?: boolean
          id?: number
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
          id?: number
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          custom?: boolean
          id?: number
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      legal_unit: {
        Row: {
          active: boolean
          birth_date: string | null
          data_source: string | null
          data_source_classification_id: number | null
          death_date: string | null
          edit_by_user_id: string
          edit_comment: string
          email_address: string | null
          enterprise_id: number | null
          external_ident: string | null
          external_ident_date: string | null
          external_ident_type: string | null
          foreign_participation_id: number | null
          free_econ_zone: boolean | null
          id: number
          legal_form_id: number | null
          name: string | null
          notes: string | null
          parent_org_link: number | null
          reorg_date: string | null
          reorg_references: number | null
          reorg_type_id: number | null
          sector_code_id: number | null
          seen_in_import_at: string | null
          short_name: string | null
          stat_ident: string | null
          stat_ident_date: string | null
          tax_reg_date: string | null
          tax_reg_ident: string | null
          telephone_no: string | null
          unit_size_id: number | null
          valid_from: string
          valid_to: string
          web_address: string | null
        }
        Insert: {
          active?: boolean
          birth_date?: string | null
          data_source?: string | null
          data_source_classification_id?: number | null
          death_date?: string | null
          edit_by_user_id: string
          edit_comment: string
          email_address?: string | null
          enterprise_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          free_econ_zone?: boolean | null
          id?: number
          legal_form_id?: number | null
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_id?: number | null
          sector_code_id?: number | null
          seen_in_import_at?: string | null
          short_name?: string | null
          stat_ident?: string | null
          stat_ident_date?: string | null
          tax_reg_date?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_from?: string
          valid_to?: string
          web_address?: string | null
        }
        Update: {
          active?: boolean
          birth_date?: string | null
          data_source?: string | null
          data_source_classification_id?: number | null
          death_date?: string | null
          edit_by_user_id?: string
          edit_comment?: string
          email_address?: string | null
          enterprise_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          free_econ_zone?: boolean | null
          id?: number
          legal_form_id?: number | null
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_id?: number | null
          sector_code_id?: number | null
          seen_in_import_at?: string | null
          short_name?: string | null
          stat_ident?: string | null
          stat_ident_date?: string | null
          tax_reg_date?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_from?: string
          valid_to?: string
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_legal_unit_data_source_classification_data_source_classific"
            columns: ["data_source_classification_id"]
            isOneToOne: false
            referencedRelation: "data_source_classification"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_data_source_classification_data_source_classific"
            columns: ["data_source_classification_id"]
            isOneToOne: false
            referencedRelation: "data_source_classification_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_data_source_classification_data_source_classific"
            columns: ["data_source_classification_id"]
            isOneToOne: false
            referencedRelation: "data_source_classification_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_foreign_participation_foreign_participation_id"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_foreign_participation_foreign_participation_id"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_foreign_participation_foreign_participation_id"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_legal_form_legal_form_id"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_legal_form_legal_form_id"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_legal_form_legal_form_id"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_sector_code_sector_code_id"
            columns: ["sector_code_id"]
            isOneToOne: false
            referencedRelation: "sector_code"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_sector_code_sector_code_id"
            columns: ["sector_code_id"]
            isOneToOne: false
            referencedRelation: "sector_code_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_sector_code_sector_code_id"
            columns: ["sector_code_id"]
            isOneToOne: false
            referencedRelation: "sector_code_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_unit_size_size_id"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_unit_size_size_id"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_unit_size_size_id"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_system"
            referencedColumns: ["id"]
          }
        ]
      }
      location: {
        Row: {
          address_part1: string | null
          address_part2: string | null
          address_part3: string | null
          enterprise_group_id: number | null
          enterprise_id: number | null
          establishment_id: number | null
          id: number
          latitude: number | null
          legal_unit_id: number | null
          location_type: Database["public"]["Enums"]["location_type"]
          longitude: number | null
          region_id: number
          updated_by_user_id: number
          valid_from: string
          valid_to: string
        }
        Insert: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: number
          latitude?: number | null
          legal_unit_id?: number | null
          location_type: Database["public"]["Enums"]["location_type"]
          longitude?: number | null
          region_id: number
          updated_by_user_id: number
          valid_from?: string
          valid_to?: string
        }
        Update: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: number
          latitude?: number | null
          legal_unit_id?: number | null
          location_type?: Database["public"]["Enums"]["location_type"]
          longitude?: number | null
          region_id?: number
          updated_by_user_id?: number
          valid_from?: string
          valid_to?: string
        }
        Relationships: [
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
            referencedRelation: "region_view"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_updated_by_user_id_fkey"
            columns: ["updated_by_user_id"]
            isOneToOne: false
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          }
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
            referencedRelation: "country_view"
            referencedColumns: ["id"]
          }
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
          id?: number
          legal_unit_id?: number | null
          person_id: number
          person_type_id?: number | null
        }
        Update: {
          establishment_id?: number | null
          id?: number
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
          }
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
          id?: number
          name?: string | null
          name_language1?: string | null
          name_language2?: string | null
        }
        Update: {
          archived?: boolean
          id?: number
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
          updated_at: string
        }
        Insert: {
          code?: string | null
          id?: number
          label?: string
          level?: number | null
          name: string
          parent_id?: number | null
          path: unknown
          updated_at?: string
        }
        Update: {
          code?: string | null
          id?: number
          label?: string
          level?: number | null
          name?: string
          parent_id?: number | null
          path?: unknown
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_region_region_parent_id"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "region"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_region_region_parent_id"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "region_view"
            referencedColumns: ["id"]
          },
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
            referencedRelation: "region_view"
            referencedColumns: ["id"]
          }
        ]
      }
      region_role: {
        Row: {
          id: number
          region_id: number
          role_id: number
        }
        Insert: {
          id?: number
          region_id: number
          role_id: number
        }
        Update: {
          id?: number
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
            referencedRelation: "region_view"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "region_role_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "statbus_role"
            referencedColumns: ["id"]
          }
        ]
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
          id?: number
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          custom?: boolean
          description?: string
          id?: number
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
          id?: number
          parent_node_id?: number | null
          report_id?: number | null
          report_url?: string | null
          resource_group?: string | null
          title?: string | null
          type?: string | null
        }
        Update: {
          archived?: boolean
          id?: number
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
          id?: number
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
          id?: number
          name?: string
          predicate?: string
          status?: number
          user_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_sample_frame_user_user_id"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          }
        ]
      }
      sector_code: {
        Row: {
          active: boolean
          code: string | null
          custom: boolean
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
          id?: number
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
          id?: number
          label?: string
          name?: string
          parent_id?: number | null
          path?: unknown
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_sector_code_sector_code_parent_id"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "sector_code"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_sector_code_sector_code_parent_id"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "sector_code_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_sector_code_sector_code_parent_id"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "sector_code_system"
            referencedColumns: ["id"]
          }
        ]
      }
      settings: {
        Row: {
          activity_category_standard_id: number
          id: number
          only_one_setting: boolean
        }
        Insert: {
          activity_category_standard_id: number
          id?: number
          only_one_setting?: boolean
        }
        Update: {
          activity_category_standard_id?: number
          id?: number
          only_one_setting?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "settings_activity_category_standard_id_fkey"
            columns: ["activity_category_standard_id"]
            isOneToOne: false
            referencedRelation: "activity_category_standard"
            referencedColumns: ["id"]
          }
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
          stat_type: Database["public"]["Enums"]["stat_type"]
        }
        Insert: {
          archived?: boolean
          code: string
          description?: string | null
          frequency: Database["public"]["Enums"]["stat_frequency"]
          id?: number
          name: string
          priority?: number | null
          stat_type: Database["public"]["Enums"]["stat_type"]
        }
        Update: {
          archived?: boolean
          code?: string
          description?: string | null
          frequency?: Database["public"]["Enums"]["stat_frequency"]
          id?: number
          name?: string
          priority?: number | null
          stat_type?: Database["public"]["Enums"]["stat_type"]
        }
        Relationships: []
      }
      stat_for_unit: {
        Row: {
          establishment_id: number
          id: number
          stat_definition_id: number
          valid_from: string
          valid_to: string
          value_bool: boolean | null
          value_float: number | null
          value_int: number | null
          value_str: string | null
        }
        Insert: {
          establishment_id: number
          id?: number
          stat_definition_id: number
          valid_from?: string
          valid_to?: string
          value_bool?: boolean | null
          value_float?: number | null
          value_int?: number | null
          value_str?: string | null
        }
        Update: {
          establishment_id?: number
          id?: number
          stat_definition_id?: number
          valid_from?: string
          valid_to?: string
          value_bool?: boolean | null
          value_float?: number | null
          value_int?: number | null
          value_str?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "stat_for_unit_stat_definition_id_fkey"
            columns: ["stat_definition_id"]
            isOneToOne: false
            referencedRelation: "stat_definition"
            referencedColumns: ["id"]
          }
        ]
      }
      statbus_role: {
        Row: {
          description: string | null
          id: number
          name: string
          role_type: Database["public"]["Enums"]["statbus_role_type"]
        }
        Insert: {
          description?: string | null
          id?: number
          name: string
          role_type: Database["public"]["Enums"]["statbus_role_type"]
        }
        Update: {
          description?: string | null
          id?: number
          name?: string
          role_type?: Database["public"]["Enums"]["statbus_role_type"]
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
          }
        ]
      }
      tag: {
        Row: {
          archived: boolean
          code: string | null
          custom: boolean
          description: string | null
          id: number
          label: string
          level: number | null
          name: string
          parent_id: number | null
          path: unknown
          updated_at: string
        }
        Insert: {
          archived?: boolean
          code?: string | null
          custom: boolean
          description?: string | null
          id?: number
          label?: string
          level?: number | null
          name: string
          parent_id?: number | null
          path: unknown
          updated_at?: string
        }
        Update: {
          archived?: boolean
          code?: string | null
          custom?: boolean
          description?: string | null
          id?: number
          label?: string
          level?: number | null
          name?: string
          parent_id?: number | null
          path?: unknown
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tag_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "tag"
            referencedColumns: ["id"]
          }
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
          id?: number
          legal_unit_id?: number | null
          tag_id: number
          updated_by_user_id: number
        }
        Update: {
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: number
          legal_unit_id?: number | null
          tag_id?: number
          updated_by_user_id?: number
        }
        Relationships: [
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
          }
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
          id?: number
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          custom?: boolean
          id?: number
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
      activity_era: {
        Row: {
          activity_category_id: number | null
          activity_type: Database["public"]["Enums"]["activity_type"] | null
          establishment_id: number | null
          id: number | null
          legal_unit_id: number | null
          updated_at: string | null
          updated_by_user_id: number | null
          valid_from: string | null
          valid_to: string | null
        }
        Insert: {
          activity_category_id?: number | null
          activity_type?: Database["public"]["Enums"]["activity_type"] | null
          establishment_id?: number | null
          id?: number | null
          legal_unit_id?: number | null
          updated_at?: string | null
          updated_by_user_id?: number | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Update: {
          activity_category_id?: number | null
          activity_type?: Database["public"]["Enums"]["activity_type"] | null
          establishment_id?: number | null
          id?: number | null
          legal_unit_id?: number | null
          updated_at?: string | null
          updated_by_user_id?: number | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "activity_activity_category_id_fkey"
            columns: ["activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_activity_category_id_fkey"
            columns: ["activity_category_id"]
            isOneToOne: false
            referencedRelation: "activity_category_available"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_updated_by_user_id_fkey"
            columns: ["updated_by_user_id"]
            isOneToOne: false
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          }
        ]
      }
      country_view: {
        Row: {
          active: boolean | null
          code_2: string | null
          code_3: string | null
          code_num: string | null
          custom: boolean | null
          id: number | null
          name: string | null
        }
        Insert: {
          active?: boolean | null
          code_2?: string | null
          code_3?: string | null
          code_num?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
        }
        Update: {
          active?: boolean | null
          code_2?: string | null
          code_3?: string | null
          code_num?: string | null
          custom?: boolean | null
          id?: number | null
          name?: string | null
        }
        Relationships: []
      }
      data_source_classification_custom: {
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
      data_source_classification_system: {
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
      legal_unit_brreg_hovedenhet_view: {
        Row: {
          navn: string | null
          organisasjonsnummer: string | null
          stiftelsesdato: string | null
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
          data_source: string | null
          data_source_classification_id: number | null
          death_date: string | null
          edit_by_user_id: string | null
          edit_comment: string | null
          email_address: string | null
          enterprise_id: number | null
          external_ident: string | null
          external_ident_date: string | null
          external_ident_type: string | null
          foreign_participation_id: number | null
          free_econ_zone: boolean | null
          id: number | null
          legal_form_id: number | null
          name: string | null
          notes: string | null
          parent_org_link: number | null
          reorg_date: string | null
          reorg_references: number | null
          reorg_type_id: number | null
          sector_code_id: number | null
          seen_in_import_at: string | null
          short_name: string | null
          stat_ident: string | null
          stat_ident_date: string | null
          tax_reg_date: string | null
          tax_reg_ident: string | null
          telephone_no: string | null
          unit_size_id: number | null
          valid_from: string | null
          valid_to: string | null
          web_address: string | null
        }
        Insert: {
          active?: boolean | null
          birth_date?: string | null
          data_source?: string | null
          data_source_classification_id?: number | null
          death_date?: string | null
          edit_by_user_id?: string | null
          edit_comment?: string | null
          email_address?: string | null
          enterprise_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          free_econ_zone?: boolean | null
          id?: number | null
          legal_form_id?: number | null
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_id?: number | null
          sector_code_id?: number | null
          seen_in_import_at?: string | null
          short_name?: string | null
          stat_ident?: string | null
          stat_ident_date?: string | null
          tax_reg_date?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_from?: string | null
          valid_to?: string | null
          web_address?: string | null
        }
        Update: {
          active?: boolean | null
          birth_date?: string | null
          data_source?: string | null
          data_source_classification_id?: number | null
          death_date?: string | null
          edit_by_user_id?: string | null
          edit_comment?: string | null
          email_address?: string | null
          enterprise_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          free_econ_zone?: boolean | null
          id?: number | null
          legal_form_id?: number | null
          name?: string | null
          notes?: string | null
          parent_org_link?: number | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_id?: number | null
          sector_code_id?: number | null
          seen_in_import_at?: string | null
          short_name?: string | null
          stat_ident?: string | null
          stat_ident_date?: string | null
          tax_reg_date?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          unit_size_id?: number | null
          valid_from?: string | null
          valid_to?: string | null
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_legal_unit_data_source_classification_data_source_classific"
            columns: ["data_source_classification_id"]
            isOneToOne: false
            referencedRelation: "data_source_classification"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_data_source_classification_data_source_classific"
            columns: ["data_source_classification_id"]
            isOneToOne: false
            referencedRelation: "data_source_classification_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_data_source_classification_data_source_classific"
            columns: ["data_source_classification_id"]
            isOneToOne: false
            referencedRelation: "data_source_classification_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_foreign_participation_foreign_participation_id"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_foreign_participation_foreign_participation_id"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_foreign_participation_foreign_participation_id"
            columns: ["foreign_participation_id"]
            isOneToOne: false
            referencedRelation: "foreign_participation_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_legal_form_legal_form_id"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_legal_form_legal_form_id"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_legal_form_legal_form_id"
            columns: ["legal_form_id"]
            isOneToOne: false
            referencedRelation: "legal_form_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            isOneToOne: false
            referencedRelation: "reorg_type_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_sector_code_sector_code_id"
            columns: ["sector_code_id"]
            isOneToOne: false
            referencedRelation: "sector_code"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_sector_code_sector_code_id"
            columns: ["sector_code_id"]
            isOneToOne: false
            referencedRelation: "sector_code_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_sector_code_sector_code_id"
            columns: ["sector_code_id"]
            isOneToOne: false
            referencedRelation: "sector_code_system"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_unit_size_size_id"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_unit_size_size_id"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_unit_size_size_id"
            columns: ["unit_size_id"]
            isOneToOne: false
            referencedRelation: "unit_size_system"
            referencedColumns: ["id"]
          }
        ]
      }
      legal_unit_region_activity_category_stats_current: {
        Row: {
          employees: string | null
          name: string | null
          physical_region_code: string | null
          postal_region_code: string | null
          primary_activity_category_code: string | null
          tax_reg_ident: string | null
        }
        Relationships: []
      }
      legal_unit_region_activity_category_stats_current_with_delete: {
        Row: {
          employees: string | null
          name: string | null
          physical_region_code: string | null
          postal_region_code: string | null
          primary_activity_category_code: string | null
          tax_reg_ident: string | null
        }
        Relationships: []
      }
      location_era: {
        Row: {
          address_part1: string | null
          address_part2: string | null
          address_part3: string | null
          enterprise_group_id: number | null
          enterprise_id: number | null
          establishment_id: number | null
          id: number | null
          latitude: number | null
          legal_unit_id: number | null
          location_type: Database["public"]["Enums"]["location_type"] | null
          longitude: number | null
          region_id: number | null
          updated_by_user_id: number | null
          valid_from: string | null
          valid_to: string | null
        }
        Insert: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: number | null
          latitude?: number | null
          legal_unit_id?: number | null
          location_type?: Database["public"]["Enums"]["location_type"] | null
          longitude?: number | null
          region_id?: number | null
          updated_by_user_id?: number | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Update: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          enterprise_group_id?: number | null
          enterprise_id?: number | null
          establishment_id?: number | null
          id?: number | null
          latitude?: number | null
          legal_unit_id?: number | null
          location_type?: Database["public"]["Enums"]["location_type"] | null
          longitude?: number | null
          region_id?: number | null
          updated_by_user_id?: number | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Relationships: [
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
            referencedRelation: "region_view"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_updated_by_user_id_fkey"
            columns: ["updated_by_user_id"]
            isOneToOne: false
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          }
        ]
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
      region_view: {
        Row: {
          code: string | null
          id: number | null
          label: string | null
          level: number | null
          name: string | null
          parent_id: number | null
          path: unknown | null
          updated_at: string | null
        }
        Insert: {
          code?: string | null
          id?: number | null
          label?: string | null
          level?: number | null
          name?: string | null
          parent_id?: number | null
          path?: unknown | null
          updated_at?: string | null
        }
        Update: {
          code?: string | null
          id?: number | null
          label?: string | null
          level?: number | null
          name?: string | null
          parent_id?: number | null
          path?: unknown | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_region_region_parent_id"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "region"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_region_region_parent_id"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "region_view"
            referencedColumns: ["id"]
          },
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
            referencedRelation: "region_view"
            referencedColumns: ["id"]
          }
        ]
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
      sector_code_custom: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
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
          id?: number | null
          label?: string | null
          name?: string | null
          parent_id?: number | null
          path?: unknown | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_sector_code_sector_code_parent_id"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "sector_code"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_sector_code_sector_code_parent_id"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "sector_code_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_sector_code_sector_code_parent_id"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "sector_code_system"
            referencedColumns: ["id"]
          }
        ]
      }
      sector_code_system: {
        Row: {
          active: boolean | null
          code: string | null
          custom: boolean | null
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
          id?: number | null
          label?: string | null
          name?: string | null
          parent_id?: number | null
          path?: unknown | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_sector_code_sector_code_parent_id"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "sector_code"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_sector_code_sector_code_parent_id"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "sector_code_custom"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_sector_code_sector_code_parent_id"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "sector_code_system"
            referencedColumns: ["id"]
          }
        ]
      }
      statistical_units: {
        Row: {
          enterprise_group_id: number | null
          enterprise_id: number | null
          establishment_id: number | null
          legal_unit_id: number | null
          name: string | null
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
      lca: {
        Args: {
          "": unknown[]
        }
        Returns: unknown
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
      text2ltree: {
        Args: {
          "": string
        }
        Returns: unknown
      }
    }
    Enums: {
      activity_type: "primary" | "secondary" | "ancilliary"
      allowed_operations: "create" | "alter" | "create_and_alter"
      data_source_priority: "trusted" | "ok" | "not_trusted"
      data_source_upload_type: "stat_units" | "activities"
      location_type: "physical" | "postal"
      person_sex: "Male" | "Female"
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
      stat_unit_type:
        | "local_unit"
        | "legal_unit"
        | "enterprise_unit"
        | "enterprise_group"
      statbus_role_type:
        | "super_user"
        | "regular_user"
        | "restricted_user"
        | "external_user"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

export type Tables<
  PublicTableNameOrOptions extends
    | keyof (Database["public"]["Tables"] & Database["public"]["Views"])
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
        Database[PublicTableNameOrOptions["schema"]]["Views"])
    : never = never
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
      Database[PublicTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : PublicTableNameOrOptions extends keyof (Database["public"]["Tables"] &
      Database["public"]["Views"])
  ? (Database["public"]["Tables"] &
      Database["public"]["Views"])[PublicTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  PublicTableNameOrOptions extends
    | keyof Database["public"]["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : PublicTableNameOrOptions extends keyof Database["public"]["Tables"]
  ? Database["public"]["Tables"][PublicTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  PublicTableNameOrOptions extends
    | keyof Database["public"]["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : PublicTableNameOrOptions extends keyof Database["public"]["Tables"]
  ? Database["public"]["Tables"][PublicTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  PublicEnumNameOrOptions extends
    | keyof Database["public"]["Enums"]
    | { schema: keyof Database },
  EnumName extends PublicEnumNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = PublicEnumNameOrOptions extends { schema: keyof Database }
  ? Database[PublicEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : PublicEnumNameOrOptions extends keyof Database["public"]["Enums"]
  ? Database["public"]["Enums"][PublicEnumNameOrOptions]
  : never

