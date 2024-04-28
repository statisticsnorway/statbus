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
        string ShortName { get; set; }
        int? ActualAddressId { get; set; }
        int? PostalAddressId { get; set; }
        Address ActualAddress { get; set; }
        Address PostalAddress { get; set; }
        bool IsDeleted { get; set; }
        decimal? Turnover { get; set; }
        StatUnitTypes UnitType { get; }
        DateTimeOffset StartPeriod { get; set; }
        DateTimeOffset EndPeriod { get; set; }
        string UserId { get; set; }
        ChangeReasons ChangeReason { get; set; }
        string EditComment { get; set; }
        int? DataSourceClassificationId { get; set; }
        int? UnitStatusId { get; set; }
        int? Employees { get; set; }
        string TaxRegId { get; set; }
        string ExternalId { get; set; }
        int? InstSectorCodeId { get; set; }
        int? LegalFormId { get; set; }
        string LiqReason { get; set; }
        SectorCode InstSectorCode { get; set; }
        ICollection<ActivityStatisticalUnit> ActivitiesUnits { get; set; }
        ICollection<CountryStatisticalUnit> ForeignParticipationCountriesUnits { get; set; }
        ICollection<PersonStatisticalUnit> PersonsUnits { get; set; }
        LegalForm LegalForm { get; set; }
    }
}
