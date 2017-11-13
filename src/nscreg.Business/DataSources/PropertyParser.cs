using Newtonsoft.Json;
using nscreg.Data.Entities;
using System;
using System.Globalization;
using System.Reflection;

namespace nscreg.Business.DataSources
{
    public static class PropertyParser
    {
        public static object ConvertOrDefault(Type type, string raw)
        {
            try
            {
                return Convert.ChangeType(raw, type, CultureInfo.InvariantCulture);
            }
            catch (Exception)
            {
                return type.GetTypeInfo().IsValueType ? Activator.CreateInstance(type) : null;
            }
        }

        public static Activity ParseActivity(string raw) => JsonConvert.DeserializeObject<Activity>(raw);

        public static Address ParseAddress(string raw) => JsonConvert.DeserializeObject<Address>(raw);

        public static Country ParseCountry(string raw) => JsonConvert.DeserializeObject<Country>(raw);

        public static LegalForm ParseLegalForm(string raw) => JsonConvert.DeserializeObject<LegalForm>(raw);

        public static Person ParsePerson(string raw) => JsonConvert.DeserializeObject<Person>(raw);

        public static SectorCode ParseSectorCode(string raw) => JsonConvert.DeserializeObject<SectorCode>(raw);

        public static DataSourceClassification ParseDataSourceClassification(string raw) =>
            JsonConvert.DeserializeObject<DataSourceClassification>(raw);
    }
}
