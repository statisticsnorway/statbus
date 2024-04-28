using nscreg.Data.Entities;

namespace nscreg.Business.Analysis.StatUnit
{
    public class AnalysisDublicateResult
    {
        public string Name { get; set; }
            public string StatId { get; set; }
            public string TaxRegId { get; set; }
            public string ExternalId { get; set; }
            public string ShortName { get; set; }
            public string TelephoneNo { get; set; }
            public Address ActualAddress { get; set; }
            public int? ActualAddressId { get; set; }
            public string EmailAddress { get; set; }
    }
}
