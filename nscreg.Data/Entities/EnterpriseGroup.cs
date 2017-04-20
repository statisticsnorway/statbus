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
        [DataAccessCommon]
        public int RegId { get; set; }  //	Automatically generated id unit
        [Display(GroupName = GroupNames.RegistrationInfo)]
        [NotMappedFor(ActionsEnum.Create)]
        public DateTime RegIdDate { get; set; } //	Date of id (ie. Date of unit entered into the register)
        [Display(GroupName = GroupNames.StatUnitInfo)]
        public string StatId { get; set; } //	The Identifier given the Statistical unit by NSO
        [Display(GroupName = GroupNames.StatUnitInfo)]
        public DateTime StatIdDate { get; set; }    //	Date of unit registered within the NSO (Might be before it was entered into this register)
        [Display(GroupName = GroupNames.RegistrationInfo)]
        public int TaxRegId { get; set; }   //	unique fiscal code from tax authorities
        [Display(GroupName = GroupNames.RegistrationInfo)]
        public DateTime TaxRegDate { get; set; }    //	Date of registration at tax authorities
        [Display(GroupName = GroupNames.RegistrationInfo)]
        public int ExternalId { get; set; } //	ID of another external data source
        [Display(GroupName = GroupNames.RegistrationInfo)]
        public int ExternalIdType { get; set; }  //	UnitType of external  id (linked to table containing possible types)
        [Display(GroupName = GroupNames.RegistrationInfo)]
        public DateTime ExternalIdDate { get; set; }    //	Date of registration in external source
        [Display(GroupName = GroupNames.RegistrationInfo)]
        public string DataSource { get; set; }  //	code of data source (linked to source table(s)
        [Display(GroupName = GroupNames.StatUnitInfo)]
        [DataAccessCommon]
        public string Name { get; set; }    //	Full name of Unit
        [Display(GroupName = GroupNames.StatUnitInfo)]
        public string ShortName { get; set; }   //	Short name of legal unit/soundex name (to make it more searchable)
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? AddressId { get; set; }   //	ID of visiting address (as given by the sources)
        [Display(GroupName = GroupNames.ContactInfo)]
        public virtual Address Address { get; set; }
        [Display(GroupName = GroupNames.ContactInfo)]
        public int PostalAddressId { get; set; } //	Id of postal address (post box or similar, if relevant)
        [Display(GroupName = GroupNames.ContactInfo)]
        public string TelephoneNo { get; set; } //
        [Display(GroupName = GroupNames.ContactInfo)]
        public string EmailAddress { get; set; }    //	
        [Display(GroupName = GroupNames.ContactInfo)]
        public string WebAddress { get; set; }  //	
        [Display(Order = 100, GroupName = GroupNames.StatUnitInfo)]
        public string EntGroupType { get; set; }    //	All-resident, multinational domestically controlled or multinational foreign controlled
        [Display(Order = 110, GroupName = GroupNames.RegistrationInfo)]
        public DateTime RegistrationDate { get; set; }  //	Date of registration
        [Display(GroupName = GroupNames.RegistrationInfo)]
        public string RegistrationReason { get; set; }  //	Reason for registration
        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.ContactInfo)]
        public DateTime LiqDateStart { get; set; }  //	Liquidation details, if relevant
        [NotMappedFor(ActionsEnum.Create)]
        [Display(GroupName = GroupNames.ContactInfo)]
        public DateTime LiqDateEnd { get; set; }    //	
        [Display(GroupName = GroupNames.LiquidationInfo)]
        public string LiqReason { get; set; }   //	
        [Display(GroupName = GroupNames.LiquidationInfo)]
        public string SuspensionStart { get; set; } //	suspension details, if relevant
        [Display(GroupName = GroupNames.LiquidationInfo)]
        public string SuspensionEnd { get; set; }   //	
        [Display(GroupName = GroupNames.ContactInfo)]
        public string ReorgTypeCode { get; set; }   //	Code of reorganization type
        [Display(GroupName = GroupNames.ContactInfo)]
        public DateTime ReorgDate { get; set; } //	
        [Display(GroupName = GroupNames.ContactInfo)]
        public string ReorgReferences { get; set; } //	Ids of other units affected by the reorganization
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? ActualAddressId { get; set; } //	Address after it has been corrected by NSO
        [Display(GroupName = GroupNames.ContactInfo)]
        public virtual Address ActualAddress { get; set; }
        [Display(GroupName = GroupNames.ContactInfo)]
        public string ContactPerson { get; set; }   //	
        [Display(GroupName = GroupNames.CapitalInfo)]
        public int Employees { get; set; }  //	Number of employees
        [Display(Order = 510, GroupName = GroupNames.StatUnitInfo)]
        public int EmployeesFte { get; set; }   //	Number of employees, full time equivalent
        [Display(GroupName = GroupNames.CapitalInfo)]
        public DateTime EmployeesYear { get; set; } //	Year of which the employee information is/was valid
        [Display(GroupName = GroupNames.CapitalInfo)]
        public DateTime EmployeesDate { get; set; } //	Date of registration of employees data
        [Display(GroupName = GroupNames.CapitalInfo)]
        public decimal Turnover { get; set; }    //	
        [Display(GroupName = GroupNames.CapitalInfo)]
        public DateTime TurnoverYear { get; set; }  //	Year of which the turnover is/was valid
        [Display(GroupName = GroupNames.CapitalInfo)]
        public DateTime TurnoveDate { get; set; }   //	Date of registration of the current turnover
        [Display(GroupName = GroupNames.CapitalInfo)]
        public string Status { get; set; }  //	
        [Display(GroupName = GroupNames.CapitalInfo)]
        public DateTime StatusDate { get; set; }    //	
        [Display(GroupName = GroupNames.CapitalInfo)]
        public string Notes { get; set; }
       
        [Reference(LookupEnum.EnterpriseUnitLookup)]
        [Display(Order = 340, GroupName = GroupNames.StatUnitInfo)]
        public virtual ICollection<EnterpriseUnit> EnterpriseUnits { get; set; }
        [Reference(LookupEnum.LegalUnitLookup)]
        [Display(GroupName = GroupNames.LinkInfo)]
        public virtual ICollection<LegalUnit> LegalUnits { get; set; }
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public bool IsDeleted { get; set; }
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? ParrentId { get; set; }
        [Display(GroupName = GroupNames.LinkInfo)]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public DateTime StartPeriod { get; set; }
        [Display(GroupName = GroupNames.LinkInfo)]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public DateTime EndPeriod { get; set; }
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual EnterpriseGroup Parrent { get; set; }
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string UserId { get; set; }
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public ChangeReasons ChangeReason { get; set; }
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string EditComment { get; set; }
    }
}
