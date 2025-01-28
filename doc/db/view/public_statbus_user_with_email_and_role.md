```sql
           View "public.statbus_user_with_email_and_role"
  Column   |          Type          | Collation | Nullable | Default 
-----------+------------------------+-----------+----------+---------
 email     | character varying(255) |           |          | 
 role_type | statbus_role_type      |           |          | 
Triggers:
    update_statbus_user_with_email_and_role INSTEAD OF UPDATE ON statbus_user_with_email_and_role FOR EACH ROW EXECUTE FUNCTION admin.trigger_update_statbus_user_with_email_and_role()

```
