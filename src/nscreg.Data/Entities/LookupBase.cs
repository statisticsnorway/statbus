namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Class entity base reference
    /// </summary>
    public abstract class LookupBase
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public bool IsDeleted { get; set; }
        public string NameLanguage1 { get; set; }
        public string NameLanguage2 { get; set; }
    }
}
