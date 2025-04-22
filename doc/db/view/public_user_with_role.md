```sql
                 View "public.user"
    Column    |     Type     | Collation | Nullable | Default 
--------------+--------------+-----------+----------+---------
 id           | integer      |           |          | 
 email        | text         |           |          | 
 statbus_role | statbus_role |           |          | 
Triggers:
    update_user_with_role INSTEAD OF UPDATE ON user_with_role FOR EACH ROW EXECUTE FUNCTION admin.trigger_update_user_with_role()

```
