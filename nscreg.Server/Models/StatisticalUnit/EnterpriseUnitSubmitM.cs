using System;

namespace nscreg.Server.Models.StatisticalUnit
{
    public class EnterpriseUnitSubmitM : StatisticalUnitSubmitM
    {
        public int EntGroupId { get; set; }
        public DateTime EntGroupIdDate { get; set; }
        public bool Commercial { get; set; }
        public string InstSectorCode { get; set; }
        public string TotalCapital { get; set; }
        public string MunCapitalShare { get; set; }
        public string StateCapitalShare { get; set; }
        public string PrivCapitalShare { get; set; }
        public string ForeignCapitalShare { get; set; }
        public string ForeignCapitalCurrency { get; set; }
        public string ActualMainActivity1 { get; set; }
        public string ActualMainActivity2 { get; set; }
        public string ActualMainActivityDate { get; set; }
        public string EntGroupRole { get; set; }

    }
}
