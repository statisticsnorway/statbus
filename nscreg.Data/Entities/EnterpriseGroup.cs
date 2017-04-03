using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;

namespace nscreg.Data.Entities
{
    public class EnterpriseGroup : IStatisticalUnit
    {
        public EnterpriseGroup()
        {
            EnterpriseUnits =new HashSet<EnterpriseUnit>();
            LegalUnits = new HashSet<LegalUnit>();
        }

        public StatUnitTypes UnitType => StatUnitTypes.EnterpriseGroup;

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit)]
        public int RegId { get; set; }  //	Automatically generated id unit
        [Display(GroupName = nameof(GroupName.RegistrationInfo))]
        public DateTime RegIdDate { get; set; } //	Date of id (ie. Date of unit entered into the register)
        [Display(GroupName = nameof(GroupName.StatUnitInfo))]
        public int StatId { get; set; } //	The Identifier given the Statistical unit by NSO
        [Display(GroupName = nameof(GroupName.StatUnitInfo))]
        public DateTime StatIdDate { get; set; }    //	Date of unit registered within the NSO (Might be before it was entered into this register)
        [Display(GroupName = nameof(GroupName.RegistrationInfo))]
        public int TaxRegId { get; set; }   //	unique fiscal code from tax authorities
        [Display(GroupName = nameof(GroupName.RegistrationInfo))]
        public DateTime TaxRegDate { get; set; }    //	Date of registration at tax authorities
        [Display(GroupName = nameof(GroupName.RegistrationInfo))]
        public int ExternalId { get; set; } //	ID of another external data source
        [Display(GroupName = nameof(GroupName.RegistrationInfo))]
        public int ExternalIdType { get; set; }  //	UnitType of external  id (linked to table containing possible types)
        [Display(GroupName = nameof(GroupName.RegistrationInfo))]
        public DateTime ExternalIdDate { get; set; }    //	Date of registration in external source
        [Display(GroupName = nameof(GroupName.RegistrationInfo))]
        public string DataSource { get; set; }  //	code of data source (linked to source table(s)
        [Display(GroupName = nameof(GroupName.StatUnitInfo))]
        public string Name { get; set; }    //	Full name of Unit
        [Display(GroupName = nameof(GroupName.StatUnitInfo))]
        public string ShortName { get; set; }   //	Short name of legal unit/soundex name (to make it more searchable)
        [Display(GroupName = nameof(GroupName.ContactInfo))]
        public int? AddressId { get; set; }   //	ID of visiting address (as given by the sources)
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual Address Address { get; set; }
        [Display(GroupName = nameof(GroupName.ContactInfo))]
        public int PostalAddressId { get; set; } //	Id of postal address (post box or similar, if relevant)
        [Display(GroupName = nameof(GroupName.ContactInfo))]
        public string TelephoneNo { get; set; } //
        [Display(GroupName = nameof(GroupName.ContactInfo))]
        public string EmailAddress { get; set; }    //	
        [Display(GroupName = nameof(GroupName.ContactInfo))]
        public string WebAddress { get; set; }  //	
        [Display(Order = 100, GroupName = nameof(GroupName.StatUnitInfo))]
        public string EntGroupType { get; set; }    //	All-resident, multinational domestically controlled or multinational foreign controlled
        [Display(Order = 110, GroupName = nameof(GroupName.RegistrationInfo))]
        public DateTime RegistrationDate { get; set; }  //	Date of registration
        public string RegistrationReason { get; set; }  //	Reason for registration
        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = nameof(GroupName.ContactInfo))]
        public DateTime LiqDateStart { get; set; }  //	Liquidation details, if relevant
        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = nameof(GroupName.ContactInfo))]
        public DateTime LiqDateEnd { get; set; }    //	
        [Display(GroupName = nameof(GroupName.LiquidationInfo))]
        public string LiqReason { get; set; }   //	
        public string SuspensionStart { get; set; } //	suspension details, if relevant
        public string SuspensionEnd { get; set; }   //	
        [Display(GroupName = nameof(GroupName.ContactInfo))]
        public string ReorgTypeCode { get; set; }   //	Code of reorganization type
        [Display(GroupName = nameof(GroupName.ContactInfo))]
        public DateTime ReorgDate { get; set; } //	
        [Display(GroupName = nameof(GroupName.ContactInfo))]
        public string ReorgReferences { get; set; } //	Ids of other units affected by the reorganization
        [Display(GroupName = nameof(GroupName.ContactInfo))]
        public int? ActualAddressId { get; set; } //	Address after it has been corrected by NSO
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual Address ActualAddress { get; set; }
        [Display(GroupName = nameof(GroupName.ContactInfo))]
        public string ContactPerson { get; set; }   //	
        [Display(GroupName = nameof(GroupName.CapitalInfo))]
        public int Employees { get; set; }  //	Number of employees
        [Display(Order = 510, GroupName = nameof(GroupName.StatUnitInfo))]
        public int EmployeesFte { get; set; }   //	Number of employees, full time equivalent
        [Display(GroupName = nameof(GroupName.CapitalInfo))]
        public DateTime EmployeesYear { get; set; } //	Year of which the employee information is/was valid
        public DateTime EmployeesDate { get; set; } //	Date of registration of employees data
        [Display(GroupName = nameof(GroupName.CapitalInfo))]
        public decimal Turnover { get; set; }    //	
        [Display(GroupName = nameof(GroupName.CapitalInfo))]
        public DateTime TurnoverYear { get; set; }  //	Year of which the turnover is/was valid
        [Display(GroupName = nameof(GroupName.CapitalInfo))]
        public DateTime TurnoveDate { get; set; }   //	Date of registration of the current turnover
        [Display(GroupName = nameof(GroupName.CapitalInfo))]
        public string Status { get; set; }  //	
        [Display(GroupName = nameof(GroupName.CapitalInfo))]
        public DateTime StatusDate { get; set; }    //	
        [Display(GroupName = nameof(GroupName.CapitalInfo))]
        public string Notes { get; set; }
       
        [Reference(LookupEnum.EnterpriseUnitLookup)]
        [Display(Order = 340, GroupName = nameof(GroupName.StatUnitInfo))]
        public virtual ICollection<EnterpriseUnit> EnterpriseUnits { get; set; }
        [Reference(LookupEnum.LegalUnitLookup)]
        [Display(GroupName = nameof(GroupName.LinkInfo))]
        public virtual ICollection<LegalUnit> LegalUnits { get; set; }
        [Display(GroupName = nameof(GroupName.LinkInfo))]
        public bool IsDeleted { get; set; }
        [Display(GroupName = nameof(GroupName.LinkInfo))]
        public int? ParrentId { get; set; }
        [Display(GroupName = nameof(GroupName.LinkInfo))]
        public DateTime StartPeriod { get; set; }
        [Display(GroupName = nameof(GroupName.LinkInfo))]
        public DateTime EndPeriod { get; set; }
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual EnterpriseGroup Parrent { get; set; }
    }
}
