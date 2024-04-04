namespace nscreg.Utilities.Configuration.StatUnitAnalysis
{
    /// <summary>
    /// Class duplication of fields
    /// </summary>
    public class Duplicates
    {
        public bool CheckName { get; set; }
        public bool CheckStatId { get; set; }
        public bool CheckTaxRegId { get; set; }
        public bool CheckExternalId { get; set; }
        public bool CheckShortName { get; set; }
        public bool CheckTelephoneNo { get; set; }
        public bool CheckAddressId { get; set; }
        public bool CheckEmailAddress { get; set; }
        public int MinimalIdenticalFieldsCount { get; set; }
    }
}
