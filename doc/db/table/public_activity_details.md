```sql
                                                                                 Table "public.activity"
      Column      |           Type           | Collation | Nullable |                            Default                            | Storage  | Compression | Stats target | Description 
------------------+--------------------------+-----------+----------+---------------------------------------------------------------+----------+-------------+--------------+-------------
 id               | integer                  |           | not null | nextval('activity_id_seq'::regclass)                          | plain    |             |              | 
 valid_after      | date                     |           | not null | generated always as ((valid_from - '1 day'::interval)) stored | plain    |             |              | 
 valid_from       | date                     |           | not null | CURRENT_DATE                                                  | plain    |             |              | 
 valid_to         | date                     |           | not null | 'infinity'::date                                              | plain    |             |              | 
 type             | activity_type            |           | not null |                                                               | plain    |             |              | 
 category_id      | integer                  |           | not null |                                                               | plain    |             |              | 
 data_source_id   | integer                  |           |          |                                                               | plain    |             |              | 
 edit_comment     | character varying(512)   |           |          |                                                               | extended |             |              | 
 edit_by_user_id  | integer                  |           | not null |                                                               | plain    |             |              | 
 edit_at          | timestamp with time zone |           | not null | statement_timestamp()                                         | plain    |             |              | 
 establishment_id | integer                  |           |          |                                                               | plain    |             |              | 
 legal_unit_id    | integer                  |           |          |                                                               | plain    |             |              | 
Indexes:
    "activity_id_daterange_excl" EXCLUDE USING gist (id WITH =, daterange(valid_after, valid_to, '[)'::text) WITH &&) DEFERRABLE
    "activity_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (id, valid_after, valid_to) DEFERRABLE
    "activity_type_category_id_establishment_id_daterange_excl" EXCLUDE USING gist (type WITH =, category_id WITH =, establishment_id WITH =, daterange(valid_after, valid_to, '[)'::text) WITH &&) DEFERRABLE
    "activity_type_category_id_establishment_id_valid_after_vali_key" UNIQUE CONSTRAINT, btree (type, category_id, establishment_id, valid_after, valid_to) DEFERRABLE
    "activity_type_category_id_legal_unit_id_daterange_excl" EXCLUDE USING gist (type WITH =, category_id WITH =, legal_unit_id WITH =, daterange(valid_after, valid_to, '[)'::text) WITH &&) DEFERRABLE
    "activity_type_category_id_legal_unit_id_valid_after_valid_t_key" UNIQUE CONSTRAINT, btree (type, category_id, legal_unit_id, valid_after, valid_to) DEFERRABLE
    "ix_activity_category_id" btree (category_id)
    "ix_activity_edit_by_user_id" btree (edit_by_user_id)
    "ix_activity_establishment_id" btree (establishment_id)
    "ix_activity_establishment_valid_after_valid_to" btree (establishment_id, valid_after, valid_to)
    "ix_activity_legal_unit_id" btree (legal_unit_id)
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL)
    "activity_valid_check" CHECK (valid_after < valid_to)
Foreign-key constraints:
    "activity_category_id_fkey" FOREIGN KEY (category_id) REFERENCES activity_category(id) ON DELETE CASCADE
    "activity_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE SET NULL
    "activity_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
Policies:
    POLICY "activity_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "activity_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "activity_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
    POLICY "regular_and_super_user_activity_access"
      TO authenticated
      USING (auth.has_one_of_statbus_roles(auth.uid(), ARRAY['super_user'::statbus_role_type, 'regular_user'::statbus_role_type]))
      WITH CHECK (auth.has_one_of_statbus_roles(auth.uid(), ARRAY['super_user'::statbus_role_type, 'regular_user'::statbus_role_type]))
    POLICY "restricted_user_activity_access"
      TO authenticated
      USING ((auth.has_statbus_role(auth.uid(), 'restricted_user'::statbus_role_type) AND auth.has_activity_category_access(auth.uid(), category_id)))
      WITH CHECK ((auth.has_statbus_role(auth.uid(), 'restricted_user'::statbus_role_type) AND auth.has_activity_category_access(auth.uid(), category_id)))
Triggers:
    activity_establishment_id_valid_fk_insert AFTER INSERT ON activity FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check('activity_establishment_id_valid')
    activity_establishment_id_valid_fk_update AFTER UPDATE OF establishment_id, valid_after, valid_to ON activity FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check('activity_establishment_id_valid')
    activity_legal_unit_id_valid_fk_insert AFTER INSERT ON activity FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check('activity_legal_unit_id_valid')
    activity_legal_unit_id_valid_fk_update AFTER UPDATE OF legal_unit_id, valid_after, valid_to ON activity FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check('activity_legal_unit_id_valid')
    trigger_prevent_activity_id_update BEFORE UPDATE OF id ON activity FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
