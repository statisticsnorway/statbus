using System;

namespace nscreg.Server.Models.StatisticalUnit
{
    public class EnterpriseGroupSubmitM
    {
        public int RegId { get; set; }
        public DateTime RegIdDate { get; set; }
        public int StatId { get; set; }
        public DateTime StatIdDate { get; set; }
        public int TaxRegId { get; set; }
        public DateTime TaxRegDate { get; set; }
        public int ExternalId { get; set; }
        public int ExternalIdType { get; set; }
        public DateTime ExternalIdDate { get; set; }
        public string DataSource { get; set; }
        public string Name { get; set; }
        public string ShortName { get; set; }
        public int AddressId { get; set; }
        public int PostalAddressId { get; set; }
        public string TelephoneNo { get; set; }
        public string EmailAddress { get; set; }
        public string WebAddress { get; set; }
        public string EntGroupType { get; set; }
        public DateTime RegistrationDate { get; set; }
        public string RegistrationReason { get; set; }
        public DateTime LiqDateStart { get; set; }
        public DateTime LiqDateEnd { get; set; }
        public string LiqReason { get; set; }
        public string SuspensionStart { get; set; }
        public string SuspensionEnd { get; set; }
        public string ReorgTypeCode { get; set; }
        public DateTime ReorgDate { get; set; }
        public string ReorgReferences { get; set; }
        public string ActualAddressId { get; set; }
        public string ContactPerson { get; set; }
        public int Employees { get; set; }
        public int EmployeesFte { get; set; }
        public DateTime EmployeesYear { get; set; }
        public DateTime EmployeesDate { get; set; }
        public string Turnover { get; set; }
        public DateTime TurnoverYear { get; set; }
        public DateTime TurnoveDate { get; set; }
        public string Status { get; set; }
        public DateTime StatusDate { get; set; }
        public string Notes { get; set; }
        public bool IsDeleted { get; set; }
    }
}
