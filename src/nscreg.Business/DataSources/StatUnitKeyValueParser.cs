using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.Utilities;
using Newtonsoft.Json;

namespace nscreg.Business.DataSources
{
    public static class StatUnitKeyValueParser
    {
        public static string GetStatIdSourceKey(IEnumerable<(string source, string target)> mapping)
            => mapping.SingleOrDefault(vm => vm.target == nameof(IStatisticalUnit.StatId)).source;

        public static string SerializeToString(IStatisticalUnit unit, IEnumerable<string> props)
            => JsonConvert.SerializeObject(
                unit,
                new JsonSerializerSettings {ContractResolver = new DynamicContractResolver(unit.GetType(), props)});

        public static void ParseAndMutateStatUnit(
            IReadOnlyDictionary<string, string> mappings,
            IReadOnlyDictionary<string, string> nextProps,
            IStatisticalUnit unit)
        {
            foreach (var kv in nextProps)
                if (mappings.TryGetValue(kv.Key, out string tmpKey))
                    UpdateObject(tmpKey, kv.Value, unit);
        }

        private static void UpdateObject(string key, string value, IStatisticalUnit unit)
        {
            var propInfo = unit.GetType().GetProperty(key);
            object res;
            switch (key)
            {
                case nameof(IStatisticalUnit.Address):
                case nameof(IStatisticalUnit.ActualAddress):
                    res = ParseAddress(value);
                    break;
                case nameof(StatisticalUnit.Persons):
                    propInfo = unit.GetType().GetProperty(nameof(StatisticalUnit.PersonsUnits));
                    res = ((StatisticalUnit) unit).PersonsUnits ?? new List<PersonStatisticalUnit>();
                    ((ICollection<PersonStatisticalUnit>) res).Add(
                        new PersonStatisticalUnit {Person = ParsePerson(value)});
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

        private static object ConvertOrDefault(Type type, string value)
        {
            try
            {
                return Convert.ChangeType(value, type, CultureInfo.InvariantCulture);
            }
            catch (Exception)
            {
                return type.GetTypeInfo().IsValueType ? Activator.CreateInstance(type) : null;
            }
        }

        private static Address ParseAddress(string value) => new Address {AddressPart1 = value};

        private static Person ParsePerson(string value) => new Person { GivenName = value };
    }
}
