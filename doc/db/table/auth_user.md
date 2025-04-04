```sql
                                          Table "auth.user"
       Column       |           Type           | Collation | Nullable |           Default            
--------------------+--------------------------+-----------+----------+------------------------------
 id                 | integer                  |           | not null | generated always as identity
 sub                | uuid                     |           | not null | gen_random_uuid()
 email              | text                     |           | not null | 
 password           | text                     |           |          | 
 encrypted_password | text                     |           | not null | 
 statbus_role       | statbus_role             |           | not null | 'regular_user'::statbus_role
 created_at         | timestamp with time zone |           | not null | now()
 updated_at         | timestamp with time zone |           | not null | now()
 last_sign_in_at    | timestamp with time zone |           |          | 
 email_confirmed_at | timestamp with time zone |           |          | 
 deleted_at         | timestamp with time zone |           |          | 
Indexes:
    "user_pkey" PRIMARY KEY, btree (id)
    "user_email_key" UNIQUE CONSTRAINT, btree (email)
    "user_sub_key" UNIQUE CONSTRAINT, btree (sub)
Referenced by:
    TABLE "activity_category_access" CONSTRAINT "activity_category_access_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE CASCADE
    TABLE "activity" CONSTRAINT "activity_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
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
    TABLE "tag_for_unit" CONSTRAINT "tag_for_unit_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    TABLE "unit_notes" CONSTRAINT "unit_notes_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
Triggers:
    create_user_role_trigger BEFORE INSERT ON auth."user" FOR EACH ROW EXECUTE FUNCTION auth.create_user_role()
    drop_user_role_trigger AFTER DELETE ON auth."user" FOR EACH ROW EXECUTE FUNCTION auth.drop_user_role()

```
