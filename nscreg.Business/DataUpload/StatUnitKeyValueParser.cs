using System;
using nscreg.Data.Entities;
using System.Collections.Generic;
using System.Globalization;
using nscreg.Utilities.Extensions;
using System.Reflection;

namespace nscreg.Business.DataUpload
{
    public static class StatUnitKeyValueParser
    {
        public static void ParseAndMutateStatUnit(
            Dictionary<string, string> mappings,
            Dictionary<string, string> nextProps,
            IStatisticalUnit unit
        ) => nextProps.ForEach(kv => UpdateObject(mappings[kv.Key], kv.Value, unit));

        private static void UpdateObject(string key, string value, IStatisticalUnit unit)
        {
            var propInfo = unit.GetType().GetProperty(key);
            var type = propInfo.PropertyType;
            var res = !string.IsNullOrEmpty(value) || Nullable.GetUnderlyingType(type) == null
                ? Type.GetTypeCode(type) == TypeCode.String
                    ? value
                    : Convert.ChangeType(value, type, CultureInfo.InvariantCulture)
                : null;
            propInfo.SetValue(unit, res);
        }
    }
}
