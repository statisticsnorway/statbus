namespace nscreg.Utilities.Configuration.DBMandatoryFields
{
    /// <summary>
    /// Legal unit class with required fields
    /// </summary>
    public class LegalUnit
    {
        public bool Market { get; set; }
        public bool LegalFormId { get; set; }
        public bool InstSectorCodeId { get; set; }
        public bool TotalCapital { get; set; }
        public bool EnterpriseUnitRegId { get; set; }
        public bool EntRegIdDate { get; set; }
        public bool LocalUnits { get; set; }
    }
}
