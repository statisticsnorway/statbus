using Newtonsoft.Json.Linq;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using Xunit;

namespace nscreg.Server.Test
{
    public class SettingsTest
    {
        [Fact]
        public void IsEqualsISettingsNamespaces()
        {
            var type = typeof(ISettings);
            var types = AppDomain.CurrentDomain.GetAssemblies()
                .SelectMany(s => s.GetTypes())
                .Where(p => type.IsAssignableFrom(p));
            Assert.Equal(types.Select(x => x.Namespace).Count(), types.Where(w => w.Namespace == type.Namespace).Count());
        }

        [Theory]
        [InlineData("appsettings.Shared.json")]
        [InlineData("appsettings.Production.json")]
        public void CheckDbMandatoryFields(string param)
        {
            using (StreamReader r = new StreamReader(param))
            {
                string json = r.ReadToEnd();
                var jObject = JObject.Parse(json);
                var dbMandatoryFields = jObject[nameof(DbMandatoryFields)];
                const BindingFlags bindingFlags = BindingFlags.Public | BindingFlags.Instance;
                var properties = typeof(DbMandatoryFields).GetProperties(bindingFlags);
                var listDbMandatoryFields = new List<string>();
                var listAppsettingDbMandatoryFields = new List<string>();

                foreach (var property in properties)
                {
                    var propertyFields = dbMandatoryFields[property.Name];
                    foreach (var value in propertyFields)
                    {
                        listAppsettingDbMandatoryFields.Add(((Newtonsoft.Json.Linq.JProperty)value).Name);
                    }
                    foreach (var fieldInfo in property.PropertyType.GetProperties())
                    {
                        listDbMandatoryFields.Add(fieldInfo.Name);
                    }
                }

                var appsetingExcept = listAppsettingDbMandatoryFields.Except(listDbMandatoryFields).ToList();
                Assert.Empty(appsetingExcept);
                var listExceptAppsettings = listDbMandatoryFields.Except(listAppsettingDbMandatoryFields).ToList();
                Assert.Empty(listExceptAppsettings);
            }
        }
    }
}
