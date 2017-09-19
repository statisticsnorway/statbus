using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Reflection;
using System.Resources;
using nscreg.Resources.Languages;

namespace nscreg.Server.Core
{
    public static class Localization
    {
        public static Dictionary<string, Dictionary<string, string>> AllResources { get; }

        static Localization()
        {
            var keys = typeof(Resource)
                .GetProperties(BindingFlags.Static | BindingFlags.Public)
                .Where(x => x.PropertyType == typeof(string))
                .ToArray();
            var resourceManager = new ResourceManager(typeof(Resource));

            AllResources = new[] {"en-GB", "ru-RU", "ky-KG"}.ToDictionary(
                x => x,
                x => keys.ToDictionary(
                    key => key.Name,
                    key => resourceManager.GetString(
                        key.Name,
                        new CultureInfo(x == "en-GB" ? string.Empty : x))));
        }
    }
}
