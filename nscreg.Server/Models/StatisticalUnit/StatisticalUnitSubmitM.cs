using System;
using System.ComponentModel.DataAnnotations;
using nscreg.Data.Enums;
using nscreg.Utilities;

namespace nscreg.Server.Models.StatisticalUnit
{
    public class StatisticalUnitSubmitM
    {

        [Required]
        public StatisticalUnitTypes UnitType { get; set; }
        //[RequiredIf(nameof(UnitType), StatisticalUnitTypes.LegalUnits)]
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
        public int RefNo { get; set; }
        [Required]
        [DataType(DataType.Text)]
        public string Name { get; set; }
        public string ShortName { get; set; }
        public int AddressId { get; set; }
        public int PostalAddressId { get; set; }
        [Required]
        [DataType(DataType.PhoneNumber, ErrorMessage = "Invalid phone number")]
        public string TelephoneNo { get; set; }
        [Required]
        [DataType(DataType.EmailAddress, ErrorMessage = "Invalid e-mail address")]
        public string EmailAddress { get; set; }
        [Required]
        [DataType(DataType.Url, ErrorMessage = "Invalid URL")]
        public string WebAddress { get; set; }
        public string RegMainActivity { get; set; }
        public DateTime RegistrationDate { get; set; }
        public string RegistrationReason { get; set; }
        public string LiqDate { get; set; }
        public string LiqReason { get; set; }
        public string SuspensionStart { get; set; }
        public string SuspensionEnd { get; set; }
        public string ReorgTypeCode { get; set; }
        public DateTime ReorgDate { get; set; }
        public string ReorgReferences { get; set; }
        public string ActualAddressId { get; set; }
        public string ContactPerson { get; set; }
        public int Employees { get; set; }
        public int NumOfPeople { get; set; }
        public DateTime EmployeesYear { get; set; }
        public DateTime EmployeesDate { get; set; }
        public string Turnover { get; set; }
        public DateTime TurnoverYear { get; set; }
        public DateTime TurnoveDate { get; set; }
        public string Status { get; set; }
        public DateTime StatusDate { get; set; }
        public string Notes { get; set; }
        public bool FreeEconZone { get; set; }
        public string ForeignParticipation { get; set; }
        public string Classified { get; set; }
        public int EnterpriseRegId { get; set; }
        public DateTime EntRegIdDate { get; set; }
        public string Founders { get; set; }
        public string Owner { get; set; }
        public string Market { get; set; }
        public string LegalForm { get; set; }
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
        public int LegalUnitId { get; set; }
        public DateTime LegalUnitIdDate { get; set; }
        public int EntGroupId { get; set; }
        public DateTime EntGroupIdDate { get; set; }
        public string Commercial { get; set; }
        public string EntGroupType { get; set; }
        public DateTime LiqDateStart { get; set; }
        public DateTime LiqDateEnd { get; set; }
        public int EmployeesFte { get; set; }
    }
}
