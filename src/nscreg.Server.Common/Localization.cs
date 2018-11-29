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
        public static Dictionary<string, Dictionary<string, string>> AllResources { get; }
        public const string LanguagePrimary = "ru-RU";
        public const string Language1 = "en-GB";
        public const string Language2 = "ky-KG";

        static Localization()
        {
            var keys = typeof(Resource)
                .GetProperties(BindingFlags.Static | BindingFlags.Public)
                .Where(x => x.PropertyType == typeof(string))
                .ToArray();
            var resourceManager = new ResourceManager(typeof(Resource));

            AllResources = new[] { Language1, LanguagePrimary, Language2 }.ToDictionary(
                x => x,
                x => keys.ToDictionary(
                    key => key.Name,
                    key => resourceManager.GetString(
                        key.Name,
                        new CultureInfo(x == Language1 ? string.Empty : x))));
        }
    }
}
