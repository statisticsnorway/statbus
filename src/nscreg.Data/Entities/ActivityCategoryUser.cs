
namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность роль вид деятельности
    /// </summary>
    public class ActivityCategoryUser
    {
        public string UserId { get; set; }
        public virtual User User { get; set; }
        public int ActivityCategoryId { get; set; }
        public virtual ActivityCategory ActivityCategory { get; set; }
    }
}
