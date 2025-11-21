```sql
                                                                     Table "auth.user"
       Column       |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
--------------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id                 | integer                  |           | not null | generated always as identity | plain    |             |              | 
 sub                | uuid                     |           | not null | gen_random_uuid()            | plain    |             |              | 
 display_name       | text                     |           | not null |                              | extended |             |              | 
 email              | text                     |           | not null |                              | extended |             |              | 
 password           | text                     |           |          |                              | extended |             |              | 
 encrypted_password | text                     |           | not null |                              | extended |             |              | 
 statbus_role       | statbus_role             |           | not null | 'regular_user'::statbus_role | plain    |             |              | 
 created_at         | timestamp with time zone |           | not null | now()                        | plain    |             |              | 
 updated_at         | timestamp with time zone |           | not null | now()                        | plain    |             |              | 
 last_sign_in_at    | timestamp with time zone |           |          |                              | plain    |             |              | 
 email_confirmed_at | timestamp with time zone |           |          |                              | plain    |             |              | 
 deleted_at         | timestamp with time zone |           |          |                              | plain    |             |              | 
Indexes:
    "user_pkey" PRIMARY KEY, btree (id)
    "user_display_name_key" UNIQUE CONSTRAINT, btree (display_name)
    "user_email_key" UNIQUE CONSTRAINT, btree (email)
    "user_sub_key" UNIQUE CONSTRAINT, btree (sub)
Check constraints:
    "user_display_name_check" CHECK (display_name <> ''::text)
Referenced by:
    TABLE "activity_category_access" CONSTRAINT "activity_category_access_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE CASCADE
    TABLE "activity" CONSTRAINT "activity_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    TABLE "auth.api_key" CONSTRAINT "api_key_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE CASCADE
    TABLE "contact" CONSTRAINT "contact_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    TABLE "enterprise" CONSTRAINT "enterprise_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    TABLE "enterprise_group" CONSTRAINT "enterprise_group_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    TABLE "establishment" CONSTRAINT "establishment_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    TABLE "external_ident" CONSTRAINT "external_ident_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    TABLE "import_definition" CONSTRAINT "import_definition_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE SET NULL
    TABLE "import_job" CONSTRAINT "import_job_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE SET NULL
    TABLE "legal_unit" CONSTRAINT "legal_unit_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    TABLE "location" CONSTRAINT "location_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    TABLE "auth.refresh_session" CONSTRAINT "refresh_session_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE CASCADE
    TABLE "region_access" CONSTRAINT "region_access_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE CASCADE
    TABLE "stat_for_unit" CONSTRAINT "stat_for_unit_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    TABLE "tag_for_unit" CONSTRAINT "tag_for_unit_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    TABLE "unit_notes" CONSTRAINT "unit_notes_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
Policies:
    POLICY "admin_all_access"
      USING (pg_has_role(CURRENT_USER, 'admin_user'::name, 'MEMBER'::text))
      WITH CHECK (pg_has_role(CURRENT_USER, 'admin_user'::name, 'MEMBER'::text))
    POLICY "select_own_user" FOR SELECT
      USING ((email = CURRENT_USER))
    POLICY "update_own_user" FOR UPDATE
      USING ((email = CURRENT_USER))
      WITH CHECK ((email = CURRENT_USER))
Not-null constraints:
    "user_id_not_null" NOT NULL "id"
    "user_sub_not_null" NOT NULL "sub"
    "user_display_name_not_null" NOT NULL "display_name"
    "user_email_not_null" NOT NULL "email"
    "user_encrypted_password_not_null" NOT NULL "encrypted_password"
    "user_statbus_role_not_null" NOT NULL "statbus_role"
    "user_created_at_not_null" NOT NULL "created_at"
    "user_updated_at_not_null" NOT NULL "updated_at"
Triggers:
    check_role_permission_trigger BEFORE INSERT OR UPDATE ON auth."user" FOR EACH ROW EXECUTE FUNCTION auth.check_role_permission()
    drop_user_role_trigger AFTER DELETE ON auth."user" FOR EACH ROW EXECUTE FUNCTION auth.drop_user_role()
    sync_user_credentials_and_roles_trigger BEFORE INSERT OR UPDATE ON auth."user" FOR EACH ROW EXECUTE FUNCTION auth.sync_user_credentials_and_roles()
Access method: heap

```
