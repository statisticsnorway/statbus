using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using Newtonsoft.Json;

namespace nscreg.Data.Entities
{
    public abstract class StatisticalUnit : IStatisticalUnit
    {
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit)]
        public int RegId { get; set; } //	Automatically generated id unit

        [NotMappedFor(ActionsEnum.Create)]
        public DateTime RegIdDate { get; set; } //	Date of id (i.e. Date of unit entered into the register)

        [Display(Order = 100, GroupName = GroupNames.StatUnitInfo)]
        public int StatId { get; set; } //	The Identifier given the Statistical unit by NSO

        [Display(Order = 200, GroupName = GroupNames.StatUnitInfo)]
        public DateTime StatIdDate { get; set; }

        //	Date of unit registered within the NSO (Might be before it was entered into this register)

        [Display(Order = 150, GroupName = GroupNames.RegistrationInfo)]
        public int TaxRegId { get; set; } //	unique fiscal code from tax authorities

        [Display(Order = 160, GroupName = GroupNames.RegistrationInfo)]
        public DateTime TaxRegDate { get; set; } //	Date of registration at tax authorities

        [Display(Order = 350, GroupName = GroupNames.RegistrationInfo)]
        public int ExternalId { get; set; } //	ID of another external data source

        [Display(Order = 370, GroupName = GroupNames.RegistrationInfo)]
        public int ExternalIdType { get; set; } //	UnitType of external  id (linked to table containing possible types)

        [Display(Order = 360, GroupName = GroupNames.RegistrationInfo)]
        public DateTime ExternalIdDate { get; set; } //	Date of registration in external source

        [Display(Order = 390, GroupName = GroupNames.RegistrationInfo)]
        public string DataSource { get; set; } //	code of data source (linked to source table(s)

        [NotMappedFor(ActionsEnum.Create)]
        public int RefNo { get; set; } //	Reference number to paper questionnaire

        [Display(Order = 120, GroupName = GroupNames.StatUnitInfo)]
        public string Name { get; set; } //	Full name of Unit

        [Display(Order = 130, GroupName = GroupNames.StatUnitInfo)]
        public string ShortName { get; set; } //	Short name of legal unit/soundex name (to make it more searchable)

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? AddressId { get; set; } //	ID of visiting address (as given by the sources)

        //[NotMappedFor(ActionsEnum.View)]
        [Display(Order = 250, GroupName = GroupNames.ContactInfo)]
        public virtual Address Address { get; set; }

        [Display(Order = 280, GroupName = GroupNames.ContactInfo)]
        public int PostalAddressId { get; set; } //	Id of postal address (post box or similar, if relevant)

        [Display(Order = 290, GroupName = GroupNames.ContactInfo)]
        public string TelephoneNo { get; set; } //

        [Display(Order = 300, GroupName = GroupNames.ContactInfo)]
        public string EmailAddress { get; set; } //

        [Display(Order = 270, GroupName = GroupNames.ContactInfo)]
        public string WebAddress { get; set; } //

        [Display(Order = 240, GroupName = GroupNames.RegistrationInfo)]
        public int? RegMainActivityId { get; set; } //	Code of main activity as originally registered  (Nace or ISIC)

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual Activity RegMainActivity { get; set; }

        [NotMappedFor(ActionsEnum.Create)]
        public DateTime RegistrationDate { get; set; } //	Date of registration

        [Display(Order = 230, GroupName = GroupNames.RegistrationInfo)]
        public string RegistrationReason { get; set; } //	Reason for registration

        [NotMappedFor(ActionsEnum.Create)]
        public string LiqDate { get; set; } //	Liquidation details, if relevant

        [NotMappedFor(ActionsEnum.Create)]
        public string LiqReason { get; set; } //

        [NotMappedFor(ActionsEnum.Create)]
        public string SuspensionStart { get; set; } //	suspension details, if relevant

        [NotMappedFor(ActionsEnum.Create)]
        public string SuspensionEnd { get; set; } //

        [NotMappedFor(ActionsEnum.Create)]
        public string ReorgTypeCode { get; set; } //	Code of reorganization type (merger, split etc)

        [NotMappedFor(ActionsEnum.Create)]
        public DateTime ReorgDate { get; set; } //

        [NotMappedFor(ActionsEnum.Create)]
        public string ReorgReferences { get; set; } //	Ids of other units affected by the reorganisation

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? ActualAddressId { get; set; } //	Address after it has been corrected by NSO
        //[NotMappedFor(ActionsEnum.View)]
        [Display(Order = 310, GroupName = GroupNames.ContactInfo)]
        public virtual Address ActualAddress { get; set; }

        [Display(Order = 260, GroupName = GroupNames.ContactInfo)]
        public string ContactPerson { get; set; } //

        [Display(Order = 500, GroupName = GroupNames.IndexInfo)]
        public int Employees { get; set; } //	Number of employees (excluding owner)

        [Display(Order = 490, GroupName = GroupNames.IndexInfo)]
        public int NumOfPeople { get; set; } //	Number of people employed (including owner)

        [Display(Order = 520, GroupName = GroupNames.IndexInfo)]
        public DateTime EmployeesYear { get; set; } //	Year of which the employee information is/was valid

        [Display(Order = 530, GroupName = GroupNames.IndexInfo)]
        public DateTime EmployeesDate { get; set; } //	Date of registration of employees data

        [Display(Order = 540, GroupName = GroupNames.IndexInfo)]
        public decimal Turnover { get; set; } //

        [Display(Order = 560, GroupName = GroupNames.IndexInfo)]
        public DateTime TurnoverYear { get; set; } //	Year of which the turnover is/was valid

        [Display(Order = 550, GroupName = GroupNames.IndexInfo)]
        public DateTime TurnoveDate { get; set; } //	Date of registration of the current turnover

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        [Display(Order = 590)]
        public StatUnitStatuses Status { get; set; } //	Active/inactive/dormant (or national classification)

        [Display(Order = 600, GroupName = GroupNames.IndexInfo)]
        public DateTime StatusDate { get; set; } //

        [Display(Order = 570, GroupName = GroupNames.IndexInfo)]
        public string Notes { get; set; } //

        [Display(Order = 470, GroupName = GroupNames.IndexInfo)]
        public bool FreeEconZone { get; set; }

        //	Yes/no (whether the unit operates in a Free economic zone with different tax rules)

        [Display(Order = 460, GroupName = GroupNames.IndexInfo)]
        public string ForeignParticipation { get; set; }

        //	Dependent on the country, this might be a variable that is irrelevant, is a yes/no question, or has a longer code list. (In Kyrgyzstan it has 9 elements)

        [Display(Order = 580, GroupName = GroupNames.IndexInfo)]
        public string Classified { get; set; } //	Whether the information about the unit is classified or not

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public bool IsDeleted { get; set; }

        public abstract StatUnitTypes UnitType { get; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual StatisticalUnit Parrent { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public int? ParrentId { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public DateTime StartPeriod { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public DateTime EndPeriod { get; set; }

        [JsonIgnore]
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual ICollection<ActivityStatisticalUnit> ActivitiesUnits { get; set; } = new HashSet<ActivityStatisticalUnit>();

        //TODO: USE VIEW MODEL
        [Display(Order = 650, GroupName = GroupNames.RegistrationInfo)]
        [NotMapped]
        public IEnumerable<Activity> Activities
        {
            get
            {
                return ActivitiesUnits.Select(v => v.Activity);
            }
            set { throw new NotImplementedException(); }
        }

        private string _userId;
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string UserId {
            get
            {
                return _userId;
            }
            set
            {
                if(value == null) throw  new Exception("UserId can't be null");
                _userId = value;
            }
        }
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public ChangeReasons ChangeReason { get; set; }
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string EditComment { get; set; }
    }
}
