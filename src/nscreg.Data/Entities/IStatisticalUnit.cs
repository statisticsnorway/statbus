using System;
using System.Collections.Generic;
using nscreg.Data.Constants;
using nscreg.Utilities.Enums;

namespace nscreg.Data.Entities
{
    public interface IStatisticalUnit
    {
        int RegId { get; set; }
        string StatId { get; set; }
        string Name { get; set; }
        int? AddressId { get; set; }
        int? ActualAddressId { get; set; }
        int? PostalAddressId { get; set; }
        Address Address { get; set; }
        Address ActualAddress { get; set; }
        Address PostalAddress { get; set; }
        bool IsDeleted { get; set; }
        decimal? Turnover { get; set; }
        DateTimeOffset StartPeriod { get; set; }
        DateTimeOffset EndPeriod { get; set; }
        string UserId { get; set; }
        ChangeReasons ChangeReason { get; set; }
        string EditComment { get; set; }
        int? DataSourceClassificationId { get; set; }
        public DataSourceClassification DataSourceClassification { get; set; }
        public UnitSize Size { get; set; }
        public UnitStatus UnitStatus { get; set; }
        public ReorgType ReorgType { get; set; }
        public RegistrationReason RegistrationReason { get; set; }
        public ForeignParticipation ForeignParticipation { get; set; }
        int? UnitStatusId { get; set; }
        int? Employees { get; set; }
        string TaxRegId { get; set; }
        string ExternalId { get; set; }
        int? InstSectorCodeId { get; set; }
        int? LegalFormId { get; set; }
        string LiqReason { get; set; }
        SectorCode InstSectorCode { get; set; }
        ICollection<ActivityLegalUnit> ActivitiesUnits { get; set; }
        ICollection<CountryForUnit> ForeignParticipationCountriesUnits { get; set; }
        ICollection<PersonForUnit> PersonsUnits { get; set; }
        LegalForm LegalForm { get; set; }
    }
}
