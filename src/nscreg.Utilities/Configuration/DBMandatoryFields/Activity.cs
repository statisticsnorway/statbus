namespace nscreg.Utilities.Configuration.DBMandatoryFields
{
    /// <summary>
    /// Класс Деятельности с обязательными полями 
    /// </summary>
    public class Activity
    {
        public bool Id { get; set; }
        public bool IdDate { get; set; }
        public bool ActivityCategoryId { get; set; }
        public bool ActivityYear { get; set; }
        public bool ActivityType { get; set; }
        public bool Employees { get; set; }
        public bool Turnover { get; set; }
    }
}
