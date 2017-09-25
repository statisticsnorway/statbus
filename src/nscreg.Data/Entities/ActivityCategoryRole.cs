
namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность роль вид деятельности
    /// </summary>
    public class ActivityCategoryRole
    {
        public string RoleId { get; set; }
        public virtual Role Role { get; set; }
        public int ActivityCategoryId { get; set; }
        public virtual ActivityCategory ActivityCategory { get; set; }
    }
}
