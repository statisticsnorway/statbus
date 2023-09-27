using nscreg.Data.Entities;

namespace nscreg.Business.Analysis.StatUnit
{
    public class AnalysisDuplicateResult
    {
        public string Name { get; set; }
            public string StatId { get; set; }
            public string TaxRegId { get; set; }
            public string ExternalId { get; set; }
            public string ShortName { get; set; }
            public string TelephoneNo { get; set; }
            public Address Address { get; set; }
            public int? AddressId { get; set; }
            public string EmailAddress { get; set; }
    }
}
