using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using Newtonsoft.Json;

namespace nscreg.Data.Entities.History
{
    /// <summary>
    ///  Класс сущность история группы предприятий
    /// </summary>
    public class EnterpriseGroupHistory : IStatisticalUnitHistory
    {
        public StatUnitTypes UnitType => StatUnitTypes.EnterpriseGroup;

        public int RegId { get; set; }

        public DateTime RegIdDate { get; set; }

        public string StatId { get; set; }

        public DateTime? StatIdDate { get; set; }

        public string Name { get; set; }

        public string ShortName { get; set; }

        public DateTime RegistrationDate { get; set; }

        public int? RegistrationReasonId { get; set; }

        public string TaxRegId { get; set; }

        public DateTime? TaxRegDate { get; set; }

        public string ExternalId { get; set; }

        public string ExternalIdType { get; set; }

        public DateTime? ExternalIdDate { get; set; }

        public string DataSource { get; set; }

        public bool IsDeleted { get; set; }

        public int? ParentId { get; set; }

        public int? AddressId { get; set; }

        public int? ActualAddressId { get; set; }

        public int? PostalAddressId { get; set; }

        public string EntGroupType { get; set; }

        public int? NumOfPeopleEmp { get; set; }

        public string TelephoneNo { get; set; }

        public string EmailAddress { get; set; }

        public string WebAddress { get; set; }

        public DateTime? LiqDateStart { get; set; }

        public DateTime? LiqDateEnd { get; set; }

        public string ReorgTypeCode { get; set; }

        public DateTime? ReorgDate { get; set; }

        public string ReorgReferences { get; set; }

        public string ContactPerson { get; set; }

        public DateTime StartPeriod { get; set; }

        public DateTime EndPeriod { get; set; }

        public string LiqReason { get; set; }

        public string SuspensionStart { get; set; }

        public string SuspensionEnd { get; set; }

        public int? Employees { get; set; }

        public int? EmployeesYear { get; set; }

        public DateTime? EmployeesDate { get; set; }

        public decimal? Turnover { get; set; }

        public int? TurnoverYear { get; set; }

        public DateTime? TurnoverDate { get; set; }

        public string Status { get; set; }

        public DateTime StatusDate { get; set; }

        public string Notes { get; set; }

        public string UserId { get; set; }

        public ChangeReasons ChangeReason { get; set; }

        public string EditComment { get; set; }

        public virtual Address Address { get; set; }

        public virtual Address ActualAddress { get; set; }

        public virtual Address PostalAddress { get; set; }

        public virtual RegistrationReason RegistrationReason { get; set; }

        public string HistoryEnterpriseUnitIds { get; set; }

        public int? RegMainActivityId
        {
            get => null;
            set { }
        }

        public int? InstSectorCodeId
        {
            get => null;
            set { }
        }

        public int? LegalFormId
        {
            get => null;
            set { }
        }

        public int? SizeId { get; set; }

        [JsonIgnore]
        public virtual UnitSize Size { get; set; }

        public int? DataSourceClassificationId { get; set; }

        [JsonIgnore]
        public virtual DataSourceClassification DataSourceClassification { get; set; }

        public int? ReorgTypeId { get; set; }

        public int? UnitStatusId { get; set; }

        [JsonIgnore]
        public SectorCode InstSectorCode { get; set; }

        [JsonIgnore]
        public LegalForm LegalForm { get; set; }
    }
}
