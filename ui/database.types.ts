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
          activity_type: number
          activity_year: number | null
          employees: number | null
          id: number
          id_date: string
          turnover: number | null
          updated_by_user_id: number
          updated_date: string
        }
        Insert: {
          activity_category_id: number
          activity_type: number
          activity_year?: number | null
          employees?: number | null
          id?: number
          id_date: string
          turnover?: number | null
          updated_by_user_id: number
          updated_date: string
        }
        Update: {
          activity_category_id?: number
          activity_type?: number
          activity_year?: number | null
          employees?: number | null
          id?: number
          id_date?: string
          turnover?: number | null
          updated_by_user_id?: number
          updated_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_activity_activity_category_activity_category_id"
            columns: ["activity_category_id"]
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_activity_user_updated_by_user_id_user_id"
            columns: ["updated_by_user_id"]
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          }
        ]
      }
      activity_category: {
        Row: {
          activity_category_level: number | null
          archived: boolean
          code: string
          dic_parent_id: number | null
          id: number
          name: string
          name_language1: string | null
          name_language2: string | null
          parent_id: number | null
          section: string
          version_id: number
        }
        Insert: {
          activity_category_level?: number | null
          archived?: boolean
          code: string
          dic_parent_id?: number | null
          id?: number
          name: string
          name_language1?: string | null
          name_language2?: string | null
          parent_id?: number | null
          section: string
          version_id: number
        }
        Update: {
          activity_category_level?: number | null
          archived?: boolean
          code?: string
          dic_parent_id?: number | null
          id?: number
          name?: string
          name_language1?: string | null
          name_language2?: string | null
          parent_id?: number | null
          section?: string
          version_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "fk_activity_category_activity_category_parent_id"
            columns: ["parent_id"]
            referencedRelation: "activity_category"
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
            referencedRelation: "activity_category"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_activity_category_role_role_role_id"
            columns: ["role_id"]
            referencedRelation: "statbus_role"
            referencedColumns: ["id"]
          }
        ]
      }
      activity_for_unit: {
        Row: {
          activity_id: number
          enterprise_group_id: number | null
          enterprise_unit_id: number | null
          id: number
          legal_unit_id: number | null
          local_unit_id: number | null
        }
        Insert: {
          activity_id: number
          enterprise_group_id?: number | null
          enterprise_unit_id?: number | null
          id?: number
          legal_unit_id?: number | null
          local_unit_id?: number | null
        }
        Update: {
          activity_id?: number
          enterprise_group_id?: number | null
          enterprise_unit_id?: number | null
          id?: number
          legal_unit_id?: number | null
          local_unit_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "activity_for_unit_enterprise_group_id_fkey"
            columns: ["enterprise_group_id"]
            referencedRelation: "enterprise_group"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_for_unit_enterprise_unit_id_fkey"
            columns: ["enterprise_unit_id"]
            referencedRelation: "enterprise_unit"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_for_unit_legal_unit_id_fkey"
            columns: ["legal_unit_id"]
            referencedRelation: "legal_unit"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_for_unit_local_unit_id_fkey"
            columns: ["local_unit_id"]
            referencedRelation: "local_unit"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_activity_for_unit_activity_activity_id"
            columns: ["activity_id"]
            referencedRelation: "activity"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_activity_for_unit_enterprise_unit_enterprise_unit_temp_id3"
            columns: ["enterprise_unit_id"]
            referencedRelation: "enterprise_unit"
            referencedColumns: ["id"]
          }
        ]
      }
      address: {
        Row: {
          address_part1: string | null
          address_part2: string | null
          address_part3: string | null
          id: number
          latitude: number | null
          longitude: number | null
          region_id: number
        }
        Insert: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          id?: number
          latitude?: number | null
          longitude?: number | null
          region_id: number
        }
        Update: {
          address_part1?: string | null
          address_part2?: string | null
          address_part3?: string | null
          id?: number
          latitude?: number | null
          longitude?: number | null
          region_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "fk_address_region_region_id"
            columns: ["region_id"]
            referencedRelation: "region"
            referencedColumns: ["id"]
          }
        ]
      }
      analysis_log: {
        Row: {
          analysis_queue_id: number
          enterprise_group_id: number | null
          enterprise_unit_id: number | null
          error_values: string | null
          id: number
          issued_at: string
          legal_unit_id: number | null
          local_unit_id: number | null
          resolved_at: string | null
          summary_messages: string | null
        }
        Insert: {
          analysis_queue_id: number
          enterprise_group_id?: number | null
          enterprise_unit_id?: number | null
          error_values?: string | null
          id?: number
          issued_at: string
          legal_unit_id?: number | null
          local_unit_id?: number | null
          resolved_at?: string | null
          summary_messages?: string | null
        }
        Update: {
          analysis_queue_id?: number
          enterprise_group_id?: number | null
          enterprise_unit_id?: number | null
          error_values?: string | null
          id?: number
          issued_at?: string
          legal_unit_id?: number | null
          local_unit_id?: number | null
          resolved_at?: string | null
          summary_messages?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "analysis_log_enterprise_group_id_fkey"
            columns: ["enterprise_group_id"]
            referencedRelation: "enterprise_group"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "analysis_log_enterprise_unit_id_fkey"
            columns: ["enterprise_unit_id"]
            referencedRelation: "enterprise_unit"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "analysis_log_legal_unit_id_fkey"
            columns: ["legal_unit_id"]
            referencedRelation: "legal_unit"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "analysis_log_local_unit_id_fkey"
            columns: ["local_unit_id"]
            referencedRelation: "local_unit"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_analysis_log_analysis_queue_analysis_queue_id"
            columns: ["analysis_queue_id"]
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
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          }
        ]
      }
      country: {
        Row: {
          archived: boolean
          code: string
          id: number
          iso_code: string | null
          name: string
          name_language1: string | null
          name_language2: string | null
        }
        Insert: {
          archived?: boolean
          code: string
          id?: number
          iso_code?: string | null
          name: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Update: {
          archived?: boolean
          code?: string
          id?: number
          iso_code?: string | null
          name?: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Relationships: []
      }
      country_for_unit: {
        Row: {
          country_id: number
          enterprise_group_id: number | null
          enterprise_unit_id: number | null
          id: number
          legal_unit_id: number | null
          local_unit_id: number | null
        }
        Insert: {
          country_id: number
          enterprise_group_id?: number | null
          enterprise_unit_id?: number | null
          id?: number
          legal_unit_id?: number | null
          local_unit_id?: number | null
        }
        Update: {
          country_id?: number
          enterprise_group_id?: number | null
          enterprise_unit_id?: number | null
          id?: number
          legal_unit_id?: number | null
          local_unit_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "country_for_unit_enterprise_group_id_fkey"
            columns: ["enterprise_group_id"]
            referencedRelation: "enterprise_group"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "country_for_unit_enterprise_unit_id_fkey"
            columns: ["enterprise_unit_id"]
            referencedRelation: "enterprise_unit"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "country_for_unit_legal_unit_id_fkey"
            columns: ["legal_unit_id"]
            referencedRelation: "legal_unit"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "country_for_unit_local_unit_id_fkey"
            columns: ["local_unit_id"]
            referencedRelation: "local_unit"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_country_for_unit_country_country_id"
            columns: ["country_id"]
            referencedRelation: "country"
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
      data_source: {
        Row: {
          allowed_operations: number
          attributes_to_check: string | null
          csv_delimiter: string | null
          csv_skip_count: number
          data_source_upload_type: number
          description: string | null
          id: number
          name: string
          original_csv_attributes: string | null
          priority: number
          restrictions: string | null
          stat_unit_type: number
          user_id: number | null
          variables_mapping: string | null
        }
        Insert: {
          allowed_operations: number
          attributes_to_check?: string | null
          csv_delimiter?: string | null
          csv_skip_count: number
          data_source_upload_type: number
          description?: string | null
          id?: number
          name: string
          original_csv_attributes?: string | null
          priority: number
          restrictions?: string | null
          stat_unit_type: number
          user_id?: number | null
          variables_mapping?: string | null
        }
        Update: {
          allowed_operations?: number
          attributes_to_check?: string | null
          csv_delimiter?: string | null
          csv_skip_count?: number
          data_source_upload_type?: number
          description?: string | null
          id?: number
          name?: string
          original_csv_attributes?: string | null
          priority?: number
          restrictions?: string | null
          stat_unit_type?: number
          user_id?: number | null
          variables_mapping?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_data_source_user_user_id"
            columns: ["user_id"]
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          }
        ]
      }
      data_source_classification: {
        Row: {
          archived: boolean
          code: string
          id: number
          name: string
          name_language1: string | null
          name_language2: string | null
        }
        Insert: {
          archived?: boolean
          code: string
          id?: number
          name: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Update: {
          archived?: boolean
          code?: string
          id?: number
          name?: string
          name_language1?: string | null
          name_language2?: string | null
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
            referencedRelation: "data_source"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_data_source_queue_user_user_id"
            columns: ["user_id"]
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
            referencedRelation: "data_source_queue"
            referencedColumns: ["id"]
          }
        ]
      }
      dictionary_version: {
        Row: {
          id: number
          version_id: number
          version_name: string | null
        }
        Insert: {
          id?: number
          version_id: number
          version_name?: string | null
        }
        Update: {
          id?: number
          version_id?: number
          version_name?: string | null
        }
        Relationships: []
      }
      enterprise_group: {
        Row: {
          actual_address_id: number | null
          address_id: number | null
          archived: boolean
          change_reason: number
          contact_person: string | null
          data_source: string | null
          data_source_classification_id: number | null
          edit_comment: string | null
          email_address: string | null
          employees: number | null
          employees_date: string | null
          employees_year: number | null
          end_period: string
          ent_group_type_id: number | null
          external_ident: string | null
          external_ident_date: string | null
          external_ident_type: string | null
          foreign_participation_id: number | null
          id: number
          liq_date_end: string | null
          liq_date_start: string | null
          liq_reason: string | null
          name: string | null
          notes: string | null
          num_of_people_emp: number | null
          postal_address_id: number | null
          reg_ident: number
          reg_ident_date: string
          registration_date: string
          registration_reason_id: number | null
          reorg_date: string | null
          reorg_references: string | null
          reorg_type_code: string | null
          reorg_type_id: number | null
          short_name: string | null
          size_id: number | null
          start_period: string
          stat_ident: string | null
          stat_ident_date: string | null
          status_date: string
          suspension_end: string | null
          suspension_start: string | null
          tax_reg_date: string | null
          tax_reg_ident: string | null
          telephone_no: string | null
          turnover: number | null
          turnover_date: string | null
          turnover_year: number | null
          unit_status_id: number | null
          user_id: number
          web_address: string | null
        }
        Insert: {
          actual_address_id?: number | null
          address_id?: number | null
          archived?: boolean
          change_reason?: number
          contact_person?: string | null
          data_source?: string | null
          data_source_classification_id?: number | null
          edit_comment?: string | null
          email_address?: string | null
          employees?: number | null
          employees_date?: string | null
          employees_year?: number | null
          end_period: string
          ent_group_type_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          id?: number
          liq_date_end?: string | null
          liq_date_start?: string | null
          liq_reason?: string | null
          name?: string | null
          notes?: string | null
          num_of_people_emp?: number | null
          postal_address_id?: number | null
          reg_ident: number
          reg_ident_date?: string
          registration_date: string
          registration_reason_id?: number | null
          reorg_date?: string | null
          reorg_references?: string | null
          reorg_type_code?: string | null
          reorg_type_id?: number | null
          short_name?: string | null
          size_id?: number | null
          start_period: string
          stat_ident?: string | null
          stat_ident_date?: string | null
          status_date: string
          suspension_end?: string | null
          suspension_start?: string | null
          tax_reg_date?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          turnover?: number | null
          turnover_date?: string | null
          turnover_year?: number | null
          unit_status_id?: number | null
          user_id: number
          web_address?: string | null
        }
        Update: {
          actual_address_id?: number | null
          address_id?: number | null
          archived?: boolean
          change_reason?: number
          contact_person?: string | null
          data_source?: string | null
          data_source_classification_id?: number | null
          edit_comment?: string | null
          email_address?: string | null
          employees?: number | null
          employees_date?: string | null
          employees_year?: number | null
          end_period?: string
          ent_group_type_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          id?: number
          liq_date_end?: string | null
          liq_date_start?: string | null
          liq_reason?: string | null
          name?: string | null
          notes?: string | null
          num_of_people_emp?: number | null
          postal_address_id?: number | null
          reg_ident?: number
          reg_ident_date?: string
          registration_date?: string
          registration_reason_id?: number | null
          reorg_date?: string | null
          reorg_references?: string | null
          reorg_type_code?: string | null
          reorg_type_id?: number | null
          short_name?: string | null
          size_id?: number | null
          start_period?: string
          stat_ident?: string | null
          stat_ident_date?: string | null
          status_date?: string
          suspension_end?: string | null
          suspension_start?: string | null
          tax_reg_date?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          turnover?: number | null
          turnover_date?: string | null
          turnover_year?: number | null
          unit_status_id?: number | null
          user_id?: number
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_enterprise_group_address_actual_address_id"
            columns: ["actual_address_id"]
            referencedRelation: "address"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_address_address_id"
            columns: ["address_id"]
            referencedRelation: "address"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_address_postal_address_id"
            columns: ["postal_address_id"]
            referencedRelation: "address"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_data_source_classification_data_source_cla"
            columns: ["data_source_classification_id"]
            referencedRelation: "data_source_classification"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_enterprise_group_type_ent_group_type_id"
            columns: ["ent_group_type_id"]
            referencedRelation: "enterprise_group_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_foreign_participation_foreign_participatio"
            columns: ["foreign_participation_id"]
            referencedRelation: "foreign_participation"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_registration_reason_registration_reason_id"
            columns: ["registration_reason_id"]
            referencedRelation: "registration_reason"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            referencedRelation: "reorg_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_unit_size_size_id"
            columns: ["size_id"]
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_group_unit_status_unit_status_id"
            columns: ["unit_status_id"]
            referencedRelation: "unit_status"
            referencedColumns: ["id"]
          }
        ]
      }
      enterprise_group_role: {
        Row: {
          archived: boolean
          code: string
          id: number
          name: string
          name_language1: string | null
          name_language2: string | null
        }
        Insert: {
          archived?: boolean
          code: string
          id?: number
          name: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Update: {
          archived?: boolean
          code?: string
          id?: number
          name?: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Relationships: []
      }
      enterprise_group_type: {
        Row: {
          archived: boolean
          code: string
          id: number
          name: string
          name_language1: string | null
          name_language2: string | null
        }
        Insert: {
          archived?: boolean
          code: string
          id?: number
          name: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Update: {
          archived?: boolean
          code?: string
          id?: number
          name?: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Relationships: []
      }
      enterprise_unit: {
        Row: {
          actual_address_id: number | null
          address_id: number | null
          archived: boolean
          change_reason: number
          classified: boolean | null
          commercial: boolean
          data_source: string | null
          data_source_classification_id: number | null
          edit_comment: string | null
          email_address: string | null
          employees: number | null
          employees_date: string | null
          employees_year: number | null
          end_period: string
          ent_group_id_date: string | null
          ent_group_role_id: number | null
          enterprise_group_id: number | null
          external_ident: string | null
          external_ident_date: string | null
          external_ident_type: string | null
          foreign_capital_currency: string | null
          foreign_capital_share: string | null
          foreign_participation_id: number | null
          free_econ_zone: boolean
          id: number
          inst_sector_code_id: number | null
          legal_form_id: number | null
          liq_date: string | null
          liq_reason: string | null
          mun_capital_share: string | null
          name: string | null
          notes: string | null
          num_of_people_emp: number | null
          parent_org_link: number | null
          postal_address_id: number | null
          priv_capital_share: string | null
          ref_no: string | null
          reg_ident: number
          reg_ident_date: string
          registration_date: string | null
          registration_reason_id: number | null
          reorg_date: string | null
          reorg_references: number | null
          reorg_type_code: string | null
          reorg_type_id: number | null
          short_name: string | null
          size_id: number | null
          start_period: string
          stat_ident: string | null
          stat_ident_date: string | null
          state_capital_share: string | null
          status_date: string | null
          suspension_end: string | null
          suspension_start: string | null
          tax_reg_date: string | null
          tax_reg_ident: string | null
          telephone_no: string | null
          total_capital: string | null
          turnover: number | null
          turnover_date: string | null
          turnover_year: number | null
          unit_status_id: number | null
          user_id: string
          web_address: string | null
        }
        Insert: {
          actual_address_id?: number | null
          address_id?: number | null
          archived?: boolean
          change_reason?: number
          classified?: boolean | null
          commercial: boolean
          data_source?: string | null
          data_source_classification_id?: number | null
          edit_comment?: string | null
          email_address?: string | null
          employees?: number | null
          employees_date?: string | null
          employees_year?: number | null
          end_period: string
          ent_group_id_date?: string | null
          ent_group_role_id?: number | null
          enterprise_group_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          foreign_capital_currency?: string | null
          foreign_capital_share?: string | null
          foreign_participation_id?: number | null
          free_econ_zone: boolean
          id?: number
          inst_sector_code_id?: number | null
          legal_form_id?: number | null
          liq_date?: string | null
          liq_reason?: string | null
          mun_capital_share?: string | null
          name?: string | null
          notes?: string | null
          num_of_people_emp?: number | null
          parent_org_link?: number | null
          postal_address_id?: number | null
          priv_capital_share?: string | null
          ref_no?: string | null
          reg_ident: number
          reg_ident_date: string
          registration_date?: string | null
          registration_reason_id?: number | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_code?: string | null
          reorg_type_id?: number | null
          short_name?: string | null
          size_id?: number | null
          start_period: string
          stat_ident?: string | null
          stat_ident_date?: string | null
          state_capital_share?: string | null
          status_date?: string | null
          suspension_end?: string | null
          suspension_start?: string | null
          tax_reg_date?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          total_capital?: string | null
          turnover?: number | null
          turnover_date?: string | null
          turnover_year?: number | null
          unit_status_id?: number | null
          user_id: string
          web_address?: string | null
        }
        Update: {
          actual_address_id?: number | null
          address_id?: number | null
          archived?: boolean
          change_reason?: number
          classified?: boolean | null
          commercial?: boolean
          data_source?: string | null
          data_source_classification_id?: number | null
          edit_comment?: string | null
          email_address?: string | null
          employees?: number | null
          employees_date?: string | null
          employees_year?: number | null
          end_period?: string
          ent_group_id_date?: string | null
          ent_group_role_id?: number | null
          enterprise_group_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          foreign_capital_currency?: string | null
          foreign_capital_share?: string | null
          foreign_participation_id?: number | null
          free_econ_zone?: boolean
          id?: number
          inst_sector_code_id?: number | null
          legal_form_id?: number | null
          liq_date?: string | null
          liq_reason?: string | null
          mun_capital_share?: string | null
          name?: string | null
          notes?: string | null
          num_of_people_emp?: number | null
          parent_org_link?: number | null
          postal_address_id?: number | null
          priv_capital_share?: string | null
          ref_no?: string | null
          reg_ident?: number
          reg_ident_date?: string
          registration_date?: string | null
          registration_reason_id?: number | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_code?: string | null
          reorg_type_id?: number | null
          short_name?: string | null
          size_id?: number | null
          start_period?: string
          stat_ident?: string | null
          stat_ident_date?: string | null
          state_capital_share?: string | null
          status_date?: string | null
          suspension_end?: string | null
          suspension_start?: string | null
          tax_reg_date?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          total_capital?: string | null
          turnover?: number | null
          turnover_date?: string | null
          turnover_year?: number | null
          unit_status_id?: number | null
          user_id?: string
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_enterprise_unit_address_actual_address_id"
            columns: ["actual_address_id"]
            referencedRelation: "address"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_unit_address_address_id"
            columns: ["address_id"]
            referencedRelation: "address"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_unit_address_postal_address_id"
            columns: ["postal_address_id"]
            referencedRelation: "address"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_unit_data_source_classification_data_source_clas"
            columns: ["data_source_classification_id"]
            referencedRelation: "data_source_classification"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_unit_enterprise_group_enterprise_group_id"
            columns: ["enterprise_group_id"]
            referencedRelation: "enterprise_group"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_unit_enterprise_group_role_ent_group_role_id"
            columns: ["ent_group_role_id"]
            referencedRelation: "enterprise_group_role"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_unit_foreign_participation_foreign_participation"
            columns: ["foreign_participation_id"]
            referencedRelation: "foreign_participation"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_unit_legal_form_legal_form_id"
            columns: ["legal_form_id"]
            referencedRelation: "legal_form"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_unit_registration_reason_registration_reason_id"
            columns: ["registration_reason_id"]
            referencedRelation: "registration_reason"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_unit_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            referencedRelation: "reorg_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_unit_sector_code_inst_sector_code_id"
            columns: ["inst_sector_code_id"]
            referencedRelation: "sector_code"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_unit_unit_size_size_id"
            columns: ["size_id"]
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_enterprise_unit_unit_status_unit_status_id"
            columns: ["unit_status_id"]
            referencedRelation: "unit_status"
            referencedColumns: ["id"]
          }
        ]
      }
      foreign_participation: {
        Row: {
          archived: boolean
          code: string
          id: number
          name: string
          name_language1: string | null
          name_language2: string | null
        }
        Insert: {
          archived?: boolean
          code: string
          id?: number
          name: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Update: {
          archived?: boolean
          code?: string
          id?: number
          name?: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Relationships: []
      }
      history: {
        Row: {
          activity_category_ids: number[] | null
          address_id: number | null
          change_reason: number
          classified: boolean | null
          data_source: string | null
          data_source_classification_id: number | null
          edit_comment: string | null
          email_address: string | null
          employees: number | null
          enterprise_group_id: number | null
          enterprise_unit_id: number | null
          external_ident: string | null
          external_ident_type: string | null
          free_econ_zone: boolean
          id: number
          legal_form_id: number | null
          legal_unit_id: number | null
          liq_date: string | null
          liq_reason: string | null
          local_unit_id: number | null
          name: string | null
          num_of_people_emp: number | null
          region_ids: number[] | null
          reorg_type_id: number | null
          sector_code_ids: number[] | null
          short_name: string | null
          size_id: number | null
          start_on: string
          stop_on: string | null
          tax_reg_ident: string | null
          telephone_no: string | null
          turnover: number | null
          unit_status_id: number | null
          user_id: string
          web_address: string | null
        }
        Insert: {
          activity_category_ids?: number[] | null
          address_id?: number | null
          change_reason?: number
          classified?: boolean | null
          data_source?: string | null
          data_source_classification_id?: number | null
          edit_comment?: string | null
          email_address?: string | null
          employees?: number | null
          enterprise_group_id?: number | null
          enterprise_unit_id?: number | null
          external_ident?: string | null
          external_ident_type?: string | null
          free_econ_zone: boolean
          id?: number
          legal_form_id?: number | null
          legal_unit_id?: number | null
          liq_date?: string | null
          liq_reason?: string | null
          local_unit_id?: number | null
          name?: string | null
          num_of_people_emp?: number | null
          region_ids?: number[] | null
          reorg_type_id?: number | null
          sector_code_ids?: number[] | null
          short_name?: string | null
          size_id?: number | null
          start_on: string
          stop_on?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          turnover?: number | null
          unit_status_id?: number | null
          user_id: string
          web_address?: string | null
        }
        Update: {
          activity_category_ids?: number[] | null
          address_id?: number | null
          change_reason?: number
          classified?: boolean | null
          data_source?: string | null
          data_source_classification_id?: number | null
          edit_comment?: string | null
          email_address?: string | null
          employees?: number | null
          enterprise_group_id?: number | null
          enterprise_unit_id?: number | null
          external_ident?: string | null
          external_ident_type?: string | null
          free_econ_zone?: boolean
          id?: number
          legal_form_id?: number | null
          legal_unit_id?: number | null
          liq_date?: string | null
          liq_reason?: string | null
          local_unit_id?: number | null
          name?: string | null
          num_of_people_emp?: number | null
          region_ids?: number[] | null
          reorg_type_id?: number | null
          sector_code_ids?: number[] | null
          short_name?: string | null
          size_id?: number | null
          start_on?: string
          stop_on?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          turnover?: number | null
          unit_status_id?: number | null
          user_id?: string
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_history_address_address_id"
            columns: ["address_id"]
            referencedRelation: "address"
            referencedColumns: ["id"]
          }
        ]
      }
      legal_form: {
        Row: {
          archived: boolean
          code: string
          id: number
          name: string
          name_language1: string | null
          name_language2: string | null
        }
        Insert: {
          archived?: boolean
          code: string
          id?: number
          name: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Update: {
          archived?: boolean
          code?: string
          id?: number
          name?: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Relationships: []
      }
      legal_unit: {
        Row: {
          actual_address_id: number | null
          address_id: number | null
          archived: boolean
          change_reason: number
          classified: boolean | null
          data_source: string | null
          data_source_classification_id: number | null
          edit_comment: string | null
          email_address: string | null
          employees: number | null
          employees_date: string | null
          employees_year: number | null
          end_period: string
          ent_reg_ident_date: string | null
          enterprise_unit_id: number | null
          external_ident: string | null
          external_ident_date: string | null
          external_ident_type: string | null
          foreign_capital_currency: string | null
          foreign_capital_share: string | null
          foreign_participation_id: number | null
          free_econ_zone: boolean
          id: number
          inst_sector_code_id: number | null
          legal_form_id: number | null
          liq_date: string | null
          liq_reason: string | null
          market: boolean | null
          mun_capital_share: string | null
          name: string | null
          notes: string | null
          num_of_people_emp: number | null
          parent_org_link: number | null
          postal_address_id: number | null
          priv_capital_share: string | null
          ref_no: string | null
          reg_ident: number
          reg_ident_date: string
          registration_date: string | null
          registration_reason_id: number | null
          reorg_date: string | null
          reorg_references: number | null
          reorg_type_code: string | null
          reorg_type_id: number | null
          short_name: string | null
          size_id: number | null
          start_period: string
          stat_ident: string | null
          stat_ident_date: string | null
          state_capital_share: string | null
          status_date: string | null
          suspension_end: string | null
          suspension_start: string | null
          tax_reg_date: string | null
          tax_reg_ident: string | null
          telephone_no: string | null
          total_capital: string | null
          turnover: number | null
          turnover_date: string | null
          turnover_year: number | null
          unit_status_id: number | null
          user_id: string
          web_address: string | null
        }
        Insert: {
          actual_address_id?: number | null
          address_id?: number | null
          archived?: boolean
          change_reason?: number
          classified?: boolean | null
          data_source?: string | null
          data_source_classification_id?: number | null
          edit_comment?: string | null
          email_address?: string | null
          employees?: number | null
          employees_date?: string | null
          employees_year?: number | null
          end_period: string
          ent_reg_ident_date?: string | null
          enterprise_unit_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          foreign_capital_currency?: string | null
          foreign_capital_share?: string | null
          foreign_participation_id?: number | null
          free_econ_zone: boolean
          id?: number
          inst_sector_code_id?: number | null
          legal_form_id?: number | null
          liq_date?: string | null
          liq_reason?: string | null
          market?: boolean | null
          mun_capital_share?: string | null
          name?: string | null
          notes?: string | null
          num_of_people_emp?: number | null
          parent_org_link?: number | null
          postal_address_id?: number | null
          priv_capital_share?: string | null
          ref_no?: string | null
          reg_ident: number
          reg_ident_date: string
          registration_date?: string | null
          registration_reason_id?: number | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_code?: string | null
          reorg_type_id?: number | null
          short_name?: string | null
          size_id?: number | null
          start_period: string
          stat_ident?: string | null
          stat_ident_date?: string | null
          state_capital_share?: string | null
          status_date?: string | null
          suspension_end?: string | null
          suspension_start?: string | null
          tax_reg_date?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          total_capital?: string | null
          turnover?: number | null
          turnover_date?: string | null
          turnover_year?: number | null
          unit_status_id?: number | null
          user_id: string
          web_address?: string | null
        }
        Update: {
          actual_address_id?: number | null
          address_id?: number | null
          archived?: boolean
          change_reason?: number
          classified?: boolean | null
          data_source?: string | null
          data_source_classification_id?: number | null
          edit_comment?: string | null
          email_address?: string | null
          employees?: number | null
          employees_date?: string | null
          employees_year?: number | null
          end_period?: string
          ent_reg_ident_date?: string | null
          enterprise_unit_id?: number | null
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          foreign_capital_currency?: string | null
          foreign_capital_share?: string | null
          foreign_participation_id?: number | null
          free_econ_zone?: boolean
          id?: number
          inst_sector_code_id?: number | null
          legal_form_id?: number | null
          liq_date?: string | null
          liq_reason?: string | null
          market?: boolean | null
          mun_capital_share?: string | null
          name?: string | null
          notes?: string | null
          num_of_people_emp?: number | null
          parent_org_link?: number | null
          postal_address_id?: number | null
          priv_capital_share?: string | null
          ref_no?: string | null
          reg_ident?: number
          reg_ident_date?: string
          registration_date?: string | null
          registration_reason_id?: number | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_code?: string | null
          reorg_type_id?: number | null
          short_name?: string | null
          size_id?: number | null
          start_period?: string
          stat_ident?: string | null
          stat_ident_date?: string | null
          state_capital_share?: string | null
          status_date?: string | null
          suspension_end?: string | null
          suspension_start?: string | null
          tax_reg_date?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          total_capital?: string | null
          turnover?: number | null
          turnover_date?: string | null
          turnover_year?: number | null
          unit_status_id?: number | null
          user_id?: string
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_legal_unit_address_actual_address_id"
            columns: ["actual_address_id"]
            referencedRelation: "address"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_address_address_id"
            columns: ["address_id"]
            referencedRelation: "address"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_address_postal_address_id"
            columns: ["postal_address_id"]
            referencedRelation: "address"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_data_source_classification_data_source_classific"
            columns: ["data_source_classification_id"]
            referencedRelation: "data_source_classification"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_enterprise_unit_enterprise_unit_temp_id"
            columns: ["enterprise_unit_id"]
            referencedRelation: "enterprise_unit"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_foreign_participation_foreign_participation_id"
            columns: ["foreign_participation_id"]
            referencedRelation: "foreign_participation"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_legal_form_legal_form_id"
            columns: ["legal_form_id"]
            referencedRelation: "legal_form"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_registration_reason_registration_reason_id"
            columns: ["registration_reason_id"]
            referencedRelation: "registration_reason"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            referencedRelation: "reorg_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_sector_code_inst_sector_code_id"
            columns: ["inst_sector_code_id"]
            referencedRelation: "sector_code"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_unit_size_size_id"
            columns: ["size_id"]
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_legal_unit_unit_status_unit_status_id"
            columns: ["unit_status_id"]
            referencedRelation: "unit_status"
            referencedColumns: ["id"]
          }
        ]
      }
      local_unit: {
        Row: {
          actual_address_id: number | null
          address_id: number | null
          archived: boolean
          change_reason: number
          classified: boolean | null
          data_source: string | null
          data_source_classification_id: number | null
          edit_comment: string | null
          email_address: string | null
          employees: number | null
          employees_date: string | null
          employees_year: number | null
          end_period: string
          external_ident: string | null
          external_ident_date: string | null
          external_ident_type: string | null
          foreign_participation_id: number | null
          free_econ_zone: boolean
          id: number
          inst_sector_code_id: number | null
          legal_form_id: number | null
          legal_unit_id: number | null
          legal_unit_id_date: string | null
          liq_date: string | null
          liq_reason: string | null
          name: string | null
          notes: string | null
          num_of_people_emp: number | null
          parent_org_link: number | null
          postal_address_id: number | null
          ref_no: string | null
          reg_ident: number
          reg_ident_date: string
          registration_date: string | null
          registration_reason_id: number | null
          reorg_date: string | null
          reorg_references: number | null
          reorg_type_code: string | null
          reorg_type_id: number | null
          short_name: string | null
          size_id: number | null
          start_period: string
          stat_ident: string | null
          stat_ident_date: string | null
          status_date: string | null
          suspension_end: string | null
          suspension_start: string | null
          tax_reg_date: string | null
          tax_reg_ident: string | null
          telephone_no: string | null
          turnover: number | null
          turnover_date: string | null
          turnover_year: number | null
          unit_status_id: number | null
          user_id: string
          web_address: string | null
        }
        Insert: {
          actual_address_id?: number | null
          address_id?: number | null
          archived?: boolean
          change_reason?: number
          classified?: boolean | null
          data_source?: string | null
          data_source_classification_id?: number | null
          edit_comment?: string | null
          email_address?: string | null
          employees?: number | null
          employees_date?: string | null
          employees_year?: number | null
          end_period: string
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          free_econ_zone: boolean
          id?: number
          inst_sector_code_id?: number | null
          legal_form_id?: number | null
          legal_unit_id?: number | null
          legal_unit_id_date?: string | null
          liq_date?: string | null
          liq_reason?: string | null
          name?: string | null
          notes?: string | null
          num_of_people_emp?: number | null
          parent_org_link?: number | null
          postal_address_id?: number | null
          ref_no?: string | null
          reg_ident: number
          reg_ident_date: string
          registration_date?: string | null
          registration_reason_id?: number | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_code?: string | null
          reorg_type_id?: number | null
          short_name?: string | null
          size_id?: number | null
          start_period: string
          stat_ident?: string | null
          stat_ident_date?: string | null
          status_date?: string | null
          suspension_end?: string | null
          suspension_start?: string | null
          tax_reg_date?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          turnover?: number | null
          turnover_date?: string | null
          turnover_year?: number | null
          unit_status_id?: number | null
          user_id: string
          web_address?: string | null
        }
        Update: {
          actual_address_id?: number | null
          address_id?: number | null
          archived?: boolean
          change_reason?: number
          classified?: boolean | null
          data_source?: string | null
          data_source_classification_id?: number | null
          edit_comment?: string | null
          email_address?: string | null
          employees?: number | null
          employees_date?: string | null
          employees_year?: number | null
          end_period?: string
          external_ident?: string | null
          external_ident_date?: string | null
          external_ident_type?: string | null
          foreign_participation_id?: number | null
          free_econ_zone?: boolean
          id?: number
          inst_sector_code_id?: number | null
          legal_form_id?: number | null
          legal_unit_id?: number | null
          legal_unit_id_date?: string | null
          liq_date?: string | null
          liq_reason?: string | null
          name?: string | null
          notes?: string | null
          num_of_people_emp?: number | null
          parent_org_link?: number | null
          postal_address_id?: number | null
          ref_no?: string | null
          reg_ident?: number
          reg_ident_date?: string
          registration_date?: string | null
          registration_reason_id?: number | null
          reorg_date?: string | null
          reorg_references?: number | null
          reorg_type_code?: string | null
          reorg_type_id?: number | null
          short_name?: string | null
          size_id?: number | null
          start_period?: string
          stat_ident?: string | null
          stat_ident_date?: string | null
          status_date?: string | null
          suspension_end?: string | null
          suspension_start?: string | null
          tax_reg_date?: string | null
          tax_reg_ident?: string | null
          telephone_no?: string | null
          turnover?: number | null
          turnover_date?: string | null
          turnover_year?: number | null
          unit_status_id?: number | null
          user_id?: string
          web_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_local_unit_address_actual_address_id"
            columns: ["actual_address_id"]
            referencedRelation: "address"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_local_unit_address_address_id"
            columns: ["address_id"]
            referencedRelation: "address"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_local_unit_address_postal_address_id"
            columns: ["postal_address_id"]
            referencedRelation: "address"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_local_unit_data_source_classification_data_source_classific"
            columns: ["data_source_classification_id"]
            referencedRelation: "data_source_classification"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_local_unit_foreign_participation_foreign_participation_id"
            columns: ["foreign_participation_id"]
            referencedRelation: "foreign_participation"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_local_unit_legal_form_legal_form_id"
            columns: ["legal_form_id"]
            referencedRelation: "legal_form"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_local_unit_legal_unit_legal_unit_id"
            columns: ["legal_unit_id"]
            referencedRelation: "legal_unit"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_local_unit_registration_reason_registration_reason_id"
            columns: ["registration_reason_id"]
            referencedRelation: "registration_reason"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_local_unit_reorg_type_reorg_type_id"
            columns: ["reorg_type_id"]
            referencedRelation: "reorg_type"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_local_unit_sector_code_inst_sector_code_id"
            columns: ["inst_sector_code_id"]
            referencedRelation: "sector_code"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_local_unit_unit_size_size_id"
            columns: ["size_id"]
            referencedRelation: "unit_size"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_local_unit_unit_status_unit_status_id"
            columns: ["unit_status_id"]
            referencedRelation: "unit_status"
            referencedColumns: ["id"]
          }
        ]
      }
      person: {
        Row: {
          address: string | null
          birth_date: string | null
          country_id: number | null
          given_name: string | null
          id: number
          id_date: string
          middle_name: string | null
          personal_id: string | null
          phone_number: string | null
          phone_number1: string | null
          sex: number | null
          surname: string | null
        }
        Insert: {
          address?: string | null
          birth_date?: string | null
          country_id?: number | null
          given_name?: string | null
          id?: number
          id_date: string
          middle_name?: string | null
          personal_id?: string | null
          phone_number?: string | null
          phone_number1?: string | null
          sex?: number | null
          surname?: string | null
        }
        Update: {
          address?: string | null
          birth_date?: string | null
          country_id?: number | null
          given_name?: string | null
          id?: number
          id_date?: string
          middle_name?: string | null
          personal_id?: string | null
          phone_number?: string | null
          phone_number1?: string | null
          sex?: number | null
          surname?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_person_country_country_id"
            columns: ["country_id"]
            referencedRelation: "country"
            referencedColumns: ["id"]
          }
        ]
      }
      person_for_unit: {
        Row: {
          enterprise_group_id: number | null
          enterprise_unit_id: number
          id: number
          legal_unit_id: number
          local_unit_id: number
          person_id: number
          person_type_id: number | null
        }
        Insert: {
          enterprise_group_id?: number | null
          enterprise_unit_id: number
          id?: number
          legal_unit_id: number
          local_unit_id: number
          person_id: number
          person_type_id?: number | null
        }
        Update: {
          enterprise_group_id?: number | null
          enterprise_unit_id?: number
          id?: number
          legal_unit_id?: number
          local_unit_id?: number
          person_id?: number
          person_type_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_person_for_unit_enterprise_group_enterprise_group_id"
            columns: ["enterprise_group_id"]
            referencedRelation: "enterprise_group"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_person_for_unit_enterprise_unit_enterprise_unit_id"
            columns: ["enterprise_unit_id"]
            referencedRelation: "enterprise_unit"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_person_for_unit_legal_unit_legal_unit_id"
            columns: ["legal_unit_id"]
            referencedRelation: "legal_unit"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_person_for_unit_local_unit_local_unit_id"
            columns: ["local_unit_id"]
            referencedRelation: "local_unit"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_person_for_unit_person_person_id"
            columns: ["person_id"]
            referencedRelation: "person"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_person_for_unit_person_type_person_type_id"
            columns: ["person_type_id"]
            referencedRelation: "person_type"
            referencedColumns: ["id"]
          }
        ]
      }
      person_type: {
        Row: {
          archived: boolean
          id: number
          name: string
          name_language1: string | null
          name_language2: string | null
        }
        Insert: {
          archived?: boolean
          id?: number
          name: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Update: {
          archived?: boolean
          id?: number
          name?: string
          name_language1?: string | null
          name_language2?: string | null
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
          adminstrative_center: string | null
          archived: boolean
          code: string
          full_path: string | null
          full_path_language1: string | null
          full_path_language2: string | null
          id: number
          name: string
          name_language1: string | null
          name_language2: string | null
          parent_id: number | null
          region_level: number | null
        }
        Insert: {
          adminstrative_center?: string | null
          archived?: boolean
          code: string
          full_path?: string | null
          full_path_language1?: string | null
          full_path_language2?: string | null
          id?: number
          name: string
          name_language1?: string | null
          name_language2?: string | null
          parent_id?: number | null
          region_level?: number | null
        }
        Update: {
          adminstrative_center?: string | null
          archived?: boolean
          code?: string
          full_path?: string | null
          full_path_language1?: string | null
          full_path_language2?: string | null
          id?: number
          name?: string
          name_language1?: string | null
          name_language2?: string | null
          parent_id?: number | null
          region_level?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_region_region_parent_id"
            columns: ["parent_id"]
            referencedRelation: "region"
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
            foreignKeyName: "fk_region_role_region_id"
            columns: ["region_id"]
            referencedRelation: "region"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_region_role_role_id"
            columns: ["role_id"]
            referencedRelation: "statbus_role"
            referencedColumns: ["id"]
          }
        ]
      }
      registration_reason: {
        Row: {
          archived: boolean
          code: string
          id: number
          name: string
          name_language1: string | null
          name_language2: string | null
        }
        Insert: {
          archived?: boolean
          code: string
          id?: number
          name: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Update: {
          archived?: boolean
          code?: string
          id?: number
          name?: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Relationships: []
      }
      reorg_type: {
        Row: {
          archived: boolean
          code: string
          id: number
          name: string
          name_language1: string | null
          name_language2: string | null
        }
        Insert: {
          archived?: boolean
          code: string
          id?: number
          name: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Update: {
          archived?: boolean
          code?: string
          id?: number
          name?: string
          name_language1?: string | null
          name_language2?: string | null
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
            referencedRelation: "statbus_user"
            referencedColumns: ["id"]
          }
        ]
      }
      sector_code: {
        Row: {
          archived: boolean
          code: string | null
          id: number
          name: string
          name_language1: string | null
          name_language2: string | null
          parent_id: number | null
        }
        Insert: {
          archived?: boolean
          code?: string | null
          id?: number
          name: string
          name_language1?: string | null
          name_language2?: string | null
          parent_id?: number | null
        }
        Update: {
          archived?: boolean
          code?: string | null
          id?: number
          name?: string
          name_language1?: string | null
          name_language2?: string | null
          parent_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_sector_code_sector_code_parent_id"
            columns: ["parent_id"]
            referencedRelation: "sector_code"
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
            referencedRelation: "statbus_role"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "statbus_user_uuid_fkey"
            columns: ["uuid"]
            referencedRelation: "users"
            referencedColumns: ["id"]
          }
        ]
      }
      unit_size: {
        Row: {
          archived: boolean
          code: number
          id: number
          name: string
          name_language1: string | null
          name_language2: string | null
        }
        Insert: {
          archived?: boolean
          code: number
          id?: number
          name: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Update: {
          archived?: boolean
          code?: number
          id?: number
          name?: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Relationships: []
      }
      unit_status: {
        Row: {
          archived: boolean
          code: string
          id: number
          name: string
          name_language1: string | null
          name_language2: string | null
        }
        Insert: {
          archived?: boolean
          code: string
          id?: number
          name: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Update: {
          archived?: boolean
          code?: string
          id?: number
          name?: string
          name_language1?: string | null
          name_language2?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      [_ in never]: never
    }
    Enums: {
      statbus_role_type: "super_user" | "restricted_user" | "external_user"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

