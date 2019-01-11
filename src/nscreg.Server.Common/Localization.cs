using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Reflection;
using System.Resources;
using nscreg.Resources.Languages;

namespace nscreg.Server.Common
{
    /// <summary>
    /// Класс конфигурации локализации языков
    /// </summary>
    public static class Localization
    {
        public static Dictionary<string, Dictionary<string, string>> AllResources { get; private set; }
        public static string LanguagePrimary { get; set; } = "ru-RU";
        public static string Language1 { get; set; } = "en-GB";
        public static string Language2 { get; set; } = "ky-KG";

        public static void Initialize()
        {
            var keys = typeof(Resource)
                .GetProperties(BindingFlags.Static | BindingFlags.Public)
                .Where(x => x.PropertyType == typeof(string))
                .ToArray();
            var resourceManager = new ResourceManager(typeof(Resource));

            AllResources = new[] { LanguagePrimary, Language1, Language2 }.ToDictionary(
                x => x,
                x => keys.ToDictionary(
                    key => key.Name,
                    key => resourceManager.GetString(
                        key.Name,
                        new CultureInfo(x == LanguagePrimary ? string.Empty : x))));
        }
    }
}
