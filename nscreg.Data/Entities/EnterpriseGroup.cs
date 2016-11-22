using System;
using System.ComponentModel.DataAnnotations;

namespace nscreg.Data.Entities
{
    public class EnterpriseGroup
    {
        [Key]
        public int RegId { get; set; }  //	Automatically generated id unit
        public DateTime RegIdDate { get; set; } //	Date of id (ie. Date of unit entered into the register)
        public int StatId { get; set; } //	The Identifier given the Statistical unit by NSO
        public DateTime StatIdDate { get; set; }    //	Date of unit registered within the NSO (Might be before it was entered into this register)
        public int TaxRegId { get; set; }   //	unique fiscal code from tax authorities
        public DateTime TaxRegDate { get; set; }    //	Date of registration at tax authorities
        public int ExternalId { get; set; } //	ID of another external data source
        public string ExternalIdType { get; set; }  //	Type of external  id (linked to table containing possible types)
        public DateTime ExternalIdDate { get; set; }    //	Date of registration in external source
        public string DataSource { get; set; }  //	code of data source (linked to source table(s)
        public string Name { get; set; }    //	Full name of Unit
        public string ShortName { get; set; }   //	Short name of legal unit/soundex name (to make it more searchable)
        public string AddressId { get; set; }   //	ID of visiting address (as given by the sources)
        public string PostalAddressId { get; set; } //	Id of postal address (post box or similar, if relevant)
        public string TelephoneNo { get; set; } //	
        public string EmailAddress { get; set; }    //	
        public string WebAddress { get; set; }  //	
        public string EntGroupType { get; set; }    //	All-resident, multinational domestically controlled or multinational foreign controlled
        public DateTime RegistrationDate { get; set; }  //	Date of registration
        public string RegistrationReason { get; set; }  //	Reason for registration
        public DateTime LiqDateStart { get; set; }  //	Liquidation details, if relevant
        public DateTime LiqDateEnd { get; set; }    //	
        public string LiqReason { get; set; }   //	
        public string SuspensionStart { get; set; } //	suspension details, if relevant
        public string SuspensionEnd { get; set; }   //	
        public string ReorgTypeCode { get; set; }   //	Code of reorganization type
        public DateTime ReorgDate { get; set; } //	
        public string ReorgReferences { get; set; } //	Ids of other units affected by the reorganization
        public string ActualAddressId { get; set; } //	Address after it has been corrected by NSO
        public string ContactPerson { get; set; }   //	
        public int Employees { get; set; }  //	Number of employees
        public int EmployeesFte { get; set; }   //	Number of employees, full time equivalent
        public DateTime EmployeesYear { get; set; } //	Year of which the employee information is/was valid
        public DateTime EmployeesDate { get; set; } //	Date of registration of employees data
        public string Turnover { get; set; }    //	
        public DateTime TurnoverYear { get; set; }  //	Year of which the turnover is/was valid
        public DateTime TurnoveDate { get; set; }   //	Date of registration of the current turnover
        public string Status { get; set; }  //	
        public DateTime StatusDate { get; set; }    //	
        public string Notes { get; set; }
        public bool IsDeleted { get; set; }
    }
}
