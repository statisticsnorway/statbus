using System;
using System.Collections.Generic;
using System.Linq;
using NLog;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Server.Common.Services.SampleFrames
{
    internal class PropertyValuesProvider
    {
        private readonly ILogger _logger = LogManager.GetCurrentClassLogger();

        private readonly Dictionary<FieldEnum, Func<IStatisticalUnit, FieldEnum, string>> _paramExtractors;

        public PropertyValuesProvider(NSCRegDbContext context)
        {
            _paramExtractors = new Dictionary<FieldEnum, Func<IStatisticalUnit, FieldEnum, string>>
            {

                [FieldEnum.ActivityCodes] = CreateReferenceValueExtractor(x =>
                    string.Join(" ", x.ActivitiesUnits.Select(y => y.Activity?.ActivityCategory.Code))),
                [FieldEnum.MainActivity] = CreateReferenceValueExtractor(x =>
                {
                    var activityCategory = x.ActivitiesUnits.Select(y => y.Activity)
                        .FirstOrDefault(y => y.ActivityType == ActivityTypes.Primary)?.ActivityCategory;
                    return activityCategory == null ? "" : $"{activityCategory?.Code} {activityCategory?.Name}";
                }),
                [FieldEnum.ForeignParticipationCountry] = CreateReferenceValueExtractor(x =>
                    string.Join(" ", x.ForeignParticipationCountriesUnits.Select(y => $"{y.Country.IsoCode} {y.Country.Name}"))),
                [FieldEnum.ContactPerson] = CreateReferenceValueExtractor(x =>string.Join(", ", x.PersonsUnits.Select(z => $"{z.Person.GivenName} {z.Person.Surname} {z.Person.MiddleName}"))),
                [FieldEnum.LegalFormId] = CreateReferenceValueExtractor(x => $"{x.LegalForm?.Code} {x.LegalForm?.Name}"),
                [FieldEnum.InstSectorCodeId] = CreateReferenceValueExtractor(x => $"{x.InstSectorCode?.Code} {x.InstSectorCode?.Name}"),
                [FieldEnum.ActualAddress] = CreateReferenceValueExtractor(x => $"{x.ActualAddress?.Region.FullPath}, {x.ActualAddress?.AddressPart1}, {x.ActualAddress?.AddressPart2}, {x.ActualAddress?.AddressPart3}"),
                [FieldEnum.PostalAddress] = CreateReferenceValueExtractor(x => $"{x.PostalAddress?.Region.FullPath}, {x.PostalAddress?.AddressPart1}, {x.PostalAddress?.AddressPart2}, {x.PostalAddress?.AddressPart3}"),

                //simple fields
                [FieldEnum.ParentId] = SimpleValueExtractor,
                [FieldEnum.Size] = SimpleValueExtractor,
                [FieldEnum.Notes] = SimpleValueExtractor,
                [FieldEnum.UnitType] = SimpleValueExtractor,
                [FieldEnum.UnitStatusId] = SimpleValueExtractor,
                [FieldEnum.Turnover] = SimpleValueExtractor,
                [FieldEnum.TurnoverYear] = SimpleValueExtractor,
                [FieldEnum.Employees] = SimpleValueExtractor,
                [FieldEnum.EmployeesYear] = SimpleValueExtractor,
                [FieldEnum.RegId] = SimpleValueExtractor,
                [FieldEnum.Name] = SimpleValueExtractor,
                [FieldEnum.StatId] = SimpleValueExtractor,
                [FieldEnum.TaxRegId] = SimpleValueExtractor,
                [FieldEnum.ExternalId] = SimpleValueExtractor,
                [FieldEnum.ShortName] = SimpleValueExtractor,
                [FieldEnum.TelephoneNo] = SimpleValueExtractor,
                [FieldEnum.EmailAddress] = SimpleValueExtractor,
                [FieldEnum.FreeEconZone] = SimpleValueExtractor,
                [FieldEnum.ForeignParticipationId] = SimpleValueExtractor
            };
        }

        public string GetValue(IStatisticalUnit unit, FieldEnum field)
        {
            return _paramExtractors[field](unit, field);
        }

        private static string SimpleValueExtractor(IStatisticalUnit unit, FieldEnum field)
        {
            return unit.GetType().GetProperty(field.ToString())?.GetValue(unit, null)?.ToString() ?? string.Empty;
        }

        private Func<IStatisticalUnit, FieldEnum, string> CreateReferenceValueExtractor(
            Func<IStatisticalUnit, string> selector)
        {
            return (unit, field) =>
            {
                try
                {
                    return selector(unit);
                }
                catch (Exception ex)
                {
                    _logger.Debug<Exception>("Error in CreateReferenceValueExtractor", ex);
                    return string.Empty;
                }
            };
        }
    }
}
