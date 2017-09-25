namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность базовый справочник
    /// </summary>
    public abstract class LookupBase
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public bool IsDeleted { get; set; }
    }
}
