namespace nscreg.Utilities.Configuration.DBMandatoryFields
{
    /// <summary>
    /// Aggregate class of required database entities
    /// </summary>
    public class DbMandatoryFields
    {
        public Activity Activity { get; set; }
        public Addresses Addresses { get; set; }
        public Enterprise Enterprise { get; set; }
        public EnterpriseGroup EnterpriseGroup { get; set; }
        public LegalUnit LegalUnit { get; set; }
        public LocalUnit LocalUnit { get; set; }
        public Person Person { get; set; }
        public StatUnit StatUnit { get; set; }
    }
}
