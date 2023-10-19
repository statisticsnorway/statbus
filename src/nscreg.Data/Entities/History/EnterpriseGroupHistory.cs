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
    ///  Class entity history group of enterprises
    /// </summary>
    public class EnterpriseGroupHistory : IStatisticalUnitHistory
    {
        public StatUnitTypes UnitType => StatUnitTypes.EnterpriseGroup;

        public int RegId { get; set; }

        public DateTimeOffset RegIdDate { get; set; }

        public string StatId { get; set; }

        public DateTimeOffset? StatIdDate { get; set; }

        public string Name { get; set; }

        public string ShortName { get; set; }

        public DateTimeOffset RegistrationDate { get; set; }

        public int? RegistrationReasonId { get; set; }

        public string TaxRegId { get; set; }

        public DateTimeOffset? TaxRegDate { get; set; }

        public string ExternalId { get; set; }

        public string ExternalIdType { get; set; }

        public DateTimeOffset? ExternalIdDate { get; set; }

        public string DataSource { get; set; }

        public bool IsDeleted { get; set; }

        public int? ParentId { get; set; }

        public int? ActualAddressId { get; set; }

        public int? PostalAddressId { get; set; }

        public int? EntGroupTypeId { get; set; }

        public EnterpriseGroupType Type { get; set; }

        public int? NumOfPeopleEmp { get; set; }

        public string TelephoneNo { get; set; }

        public string EmailAddress { get; set; }

        public string WebAddress { get; set; }

        public DateTimeOffset? LiqDateStart { get; set; }

        public DateTimeOffset? LiqDateEnd { get; set; }

        public string ReorgTypeCode { get; set; }

        public DateTimeOffset? ReorgDate { get; set; }

        public string ReorgReferences { get; set; }

        public string ContactPerson { get; set; }

        public DateTimeOffset StartPeriod { get; set; }

        public DateTimeOffset EndPeriod { get; set; }

        public int? LegalFormId { get; set; }
        public string LiqReason { get; set; }

        public string SuspensionStart { get; set; }

        public string SuspensionEnd { get; set; }

        public int? Employees { get; set; }

        public int? EmployeesYear { get; set; }

        public DateTimeOffset? EmployeesDate { get; set; }

        public decimal? Turnover { get; set; }

        public int? TurnoverYear { get; set; }

        public DateTimeOffset? TurnoverDate { get; set; }

        public DateTimeOffset StatusDate { get; set; }

        public string Notes { get; set; }

        public string UserId { get; set; }

        public ChangeReasons ChangeReason { get; set; }

        public string EditComment { get; set; }

        public virtual Address Address { get; set; }

        public virtual Address ActualAddress { get; set; }

        public virtual Address PostalAddress { get; set; }

        public virtual RegistrationReason RegistrationReason { get; set; }

        public string HistoryEnterpriseUnitIds { get; set; }

        public int? InstSectorCodeId
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

        public ReorgType ReorgType { get; set; }
        public UnitStatus UnitStatus { get; set; }

        public int? UnitStatusId { get; set; }

        [JsonIgnore]
        public SectorCode InstSectorCode { get; set; }

        public LegalForm LegalForm { get; set; }
    }
}
