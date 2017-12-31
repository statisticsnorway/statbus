namespace nscreg.Data.Entities
{
    /// <summary>
    /// Binding entity with Statistical Unit and Country
    /// </summary>
    public class CountryStatisticalUnit : IIdentifiable
    {
        public int UnitId { get; set; }
        public virtual StatisticalUnit Unit { get; set; }

        public int CountryId { get; set; }
        public virtual Country Country { get; set; }

        public int Id => CountryId;
    }
}
