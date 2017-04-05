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
        public DateTime RegIdDate { get; set; } //	Date of id (ie. Date of unit entered into the register)
        public int StatId { get; set; } //	The Identifier given the Statistical unit by NSO
        public DateTime StatIdDate { get; set; }    //	Date of unit registered within the NSO (Might be before it was entered into this register)
        public int TaxRegId { get; set; }   //	unique fiscal code from tax authorities
        public DateTime TaxRegDate { get; set; }    //	Date of registration at tax authorities
        public int ExternalId { get; set; } //	ID of another external data source
        public int ExternalIdType { get; set; }  //	UnitType of external  id (linked to table containing possible types)
        public DateTime ExternalIdDate { get; set; }    //	Date of registration in external source
        public string DataSource { get; set; }  //	code of data source (linked to source table(s)
        public string Name { get; set; }    //	Full name of Unit
        public string ShortName { get; set; }   //	Short name of legal unit/soundex name (to make it more searchable)
        public int? AddressId { get; set; }   //	ID of visiting address (as given by the sources)
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual Address Address { get; set; }
        public int PostalAddressId { get; set; } //	Id of postal address (post box or similar, if relevant)
        public string TelephoneNo { get; set; } //	
        public string EmailAddress { get; set; }    //	
        public string WebAddress { get; set; }  //	
        [Display(Order = 100)]
        public string EntGroupType { get; set; }    //	All-resident, multinational domestically controlled or multinational foreign controlled
        [Display(Order = 110)]
        public DateTime RegistrationDate { get; set; }  //	Date of registration
        public string RegistrationReason { get; set; }  //	Reason for registration
        [NotMappedFor(ActionsEnum.Create)]
        public DateTime LiqDateStart { get; set; }  //	Liquidation details, if relevant
        [NotMappedFor(ActionsEnum.Create)]
        public DateTime LiqDateEnd { get; set; }    //	
        public string LiqReason { get; set; }   //	
        public string SuspensionStart { get; set; } //	suspension details, if relevant
        public string SuspensionEnd { get; set; }   //	
        public string ReorgTypeCode { get; set; }   //	Code of reorganization type
        public DateTime ReorgDate { get; set; } //	
        public string ReorgReferences { get; set; } //	Ids of other units affected by the reorganization
        public int? ActualAddressId { get; set; } //	Address after it has been corrected by NSO
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual Address ActualAddress { get; set; }
        public string ContactPerson { get; set; }   //	
        public int Employees { get; set; }  //	Number of employees
        [Display(Order = 510)]
        public int EmployeesFte { get; set; }   //	Number of employees, full time equivalent
        public DateTime EmployeesYear { get; set; } //	Year of which the employee information is/was valid
        public DateTime EmployeesDate { get; set; } //	Date of registration of employees data
     
        public decimal Turnover { get; set; }    //	
        public DateTime TurnoverYear { get; set; }  //	Year of which the turnover is/was valid
        public DateTime TurnoveDate { get; set; }   //	Date of registration of the current turnover
        public string Status { get; set; }  //	
        public DateTime StatusDate { get; set; }    //	
        public string Notes { get; set; }
       
        [Reference(LookupEnum.EnterpriseUnitLookup)]
        [Display(Order = 340)]
        public virtual ICollection<EnterpriseUnit> EnterpriseUnits { get; set; }
        [Reference(LookupEnum.LegalUnitLookup)]
        public virtual ICollection<LegalUnit> LegalUnits { get; set; }
        public bool IsDeleted { get; set; }
        public int? ParrentId { get; set; }
        public DateTime StartPeriod { get; set; }
        public DateTime EndPeriod { get; set; }
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual EnterpriseGroup Parrent { get; set; }
        private string _userId;
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string UserId
        {
            get
            {
                return _userId;
            }
            set
            {
                if (value == null) throw new Exception("UserId can't be null");
                _userId = value;
            }
        }
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public ChangeReasons ChangeReason { get; set; }
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string EditComment { get; set; }
    }
}
