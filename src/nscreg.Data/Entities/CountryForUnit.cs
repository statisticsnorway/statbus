namespace nscreg.Data.Entities
{
    /// <summary>
    /// Binding entity with Statistical Unit and Country
    /// </summary>
    public class CountryForUnit : IIdentifiable
    {
        public int? LocalUnitId { get; set; }
        public virtual LocalUnit LocalUnit { get; set; }
        public int? LegalUnitId { get; set; }
        public virtual LegalUnit LegalUnit { get; set; }
        public int? EnterpriseUnitId { get; set; }
        public virtual EnterpriseUnit EnterpriseUnit { get; set; }
        public int? EnterpriseGroupId { get; set; }
        public virtual EnterpriseGroup EnterpriseGroup { get; set; }

        public int CountryId { get; set; }
        public virtual Country Country { get; set; }

        public int Id => CountryId;
    }
}
