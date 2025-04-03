```sql
           View "public.user_with_role"
  Column   |          Type          | Collation | Nullable | Default 
-----------+------------------------+-----------+----------+---------
 email     | character varying(255) |           |          | 
 role_type | statbus_role_type      |           |          | 
Triggers:
    update_user_with_role INSTEAD OF UPDATE ON user_with_role FOR EACH ROW EXECUTE FUNCTION admin.trigger_update_user_with_role()

```
