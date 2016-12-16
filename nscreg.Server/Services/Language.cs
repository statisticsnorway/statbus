using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Reflection;
using System.Resources;
using nscreg.Resources.Lang;

namespace nscreg.Server.Services
{
    public static class Language
    {
        public static Dictionary<string, Dictionary<string, string>> AllResources { get; }

        static Language()
        {
            var keys = typeof(Resource).GetProperties(BindingFlags.Static | BindingFlags.Public).Where(x => x.PropertyType == typeof(string));
            var resourceManager = new ResourceManager(typeof(Resource));
            AllResources = new Dictionary<string, Dictionary<string, string>>
            {
                {
                    "en-GB",
                    keys.ToDictionary(key => key.Name,
                        key => resourceManager.GetString(key.Name, new CultureInfo("")))
                },
                {
                    "ru-RU",
                    keys.ToDictionary(key => key.Name,
                        key => resourceManager.GetString(key.Name, new CultureInfo("ru-RU")))
                },
                {
                    "ky-KG",
                    keys.ToDictionary(key => key.Name,
                        key => resourceManager.GetString(key.Name, new CultureInfo("ky-KG")))
                }
            };
        }
    }
}
