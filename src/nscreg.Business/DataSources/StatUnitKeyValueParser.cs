using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.Utilities;
using Newtonsoft.Json;
using static nscreg.Business.DataSources.PropertyParser;

namespace nscreg.Business.DataSources
{
    public static class StatUnitKeyValueParser
    {
        public static string GetStatIdSourceKey(IEnumerable<(string source, string target)> mapping)
            => mapping.SingleOrDefault(vm => vm.target == nameof(StatisticalUnit.StatId)).source;

        public static string SerializeToString(StatisticalUnit unit, IEnumerable<string> props)
            => JsonConvert.SerializeObject(
                unit,
                new JsonSerializerSettings { ContractResolver = new DynamicContractResolver(unit.GetType(), props) });

        public static void ParseAndMutateStatUnit(
            IReadOnlyDictionary<string, string> mappings,
            IReadOnlyDictionary<string, string> nextProps,
            StatisticalUnit unit)
        {
            foreach (var kv in nextProps)
                if (mappings.TryGetValue(kv.Key, out var tmpKey))
                    UpdateObject(tmpKey, kv.Value, unit);
        }

        private static void UpdateObject(string key, string value, StatisticalUnit unit)
        {
            var propInfo = unit.GetType().GetProperty(key);
            object res;
            switch (key)
            {
                case nameof(StatisticalUnit.Address):
                case nameof(StatisticalUnit.ActualAddress):
                    res = ParseAddress(value);
                    break;
                case nameof(StatisticalUnit.Activities):
                    propInfo = unit.GetType().GetProperty(nameof(StatisticalUnit.ActivitiesUnits));
                    res = unit.ActivitiesUnits ?? new List<ActivityStatisticalUnit>();
                    ((ICollection<ActivityStatisticalUnit>)res).Add(
                        new ActivityStatisticalUnit { Activity = ParseActivity(value) });
                    break;
                case nameof(StatisticalUnit.ForeignParticipationCountry):
                    res = ParseCountry(value);
                    break;
                case nameof(StatisticalUnit.LegalForm):
                    res = ParseLegalForm(value);
                    break;
                case nameof(StatisticalUnit.Persons):
                    propInfo = unit.GetType().GetProperty(nameof(StatisticalUnit.PersonsUnits));
                    res = unit.PersonsUnits ?? new List<PersonStatisticalUnit>();
                    ((ICollection<PersonStatisticalUnit>)res).Add(
                        new PersonStatisticalUnit { Person = ParsePerson(value) });
                    break;
                case nameof(StatisticalUnit.InstSectorCode):
                    res = ParseSectorCode(value);
                    break;
                default:
                    var type = propInfo.PropertyType;
                    var underlyingType = Nullable.GetUnderlyingType(type);
                    res = !string.IsNullOrEmpty(value) || underlyingType == null
                        ? Type.GetTypeCode(type) == TypeCode.String
                            ? value
                            : ConvertOrDefault(underlyingType ?? type, value)
                        : null;
                    break;
            }
            propInfo.SetValue(unit, res);
        }
    }
}
