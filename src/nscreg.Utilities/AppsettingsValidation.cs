using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using nscreg.Utilities.Configuration;
using System;
using System.ComponentModel.DataAnnotations;
using System.Linq;

namespace nscreg.Utilities
{
    public static class AppsettingsValidation
    {
        public static IConfigurationSection Validate<T>(this IConfigurationSection configurationSection, ILogger logger)
        where T: ISettings
        {
            bool isValid = true;
            Type typeConfigurationSection = Type.GetType($"{typeof(ISettings).Namespace}.{configurationSection.Key}");
            var configurationSectionProperties = configurationSection.GetChildren();
            foreach (var propertyInfo in typeConfigurationSection.GetProperties())
            {
                var value = configurationSectionProperties.FirstOrDefault(x => x.Key == propertyInfo.Name);
                if (value == null)
                {
                    isValid = false;
                    logger.LogError($"Check appsettings. {typeConfigurationSection.Name}.{propertyInfo.Name} does not exist in appsettings.");
                }
                else
                {
                    if (Attribute.IsDefined(propertyInfo, typeof(RequiredAttribute)) && string.IsNullOrEmpty(value.Value))
                    {
                        isValid = false;
                        logger.LogError($"Check appsettings. {typeConfigurationSection.Name}.{propertyInfo.Name} is required.");
                    }
                }
            }
            if (!isValid) throw new Exception("Incorrect appsettings.");
            return configurationSection;
        }
    }
}
