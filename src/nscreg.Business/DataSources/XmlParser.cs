using System;
using System.Collections.Generic;
using System.Linq;
using System.Xml.Linq;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;

namespace nscreg.Business.DataSources
{
    public static class XmlParser
    {
        private readonly static string[] StatisticalUnitArrayPropertyNames = new[] { nameof(StatisticalUnit.Activities), nameof(StatisticalUnit.Persons), nameof(StatisticalUnit.ForeignParticipationCountriesUnits) };
        public static IEnumerable<XElement> GetRawEntities(XContainer doc)
        {
            var typeNames = Enum.GetNames(typeof(StatUnitTypes));
            while (true)
            {
                if (doc.Nodes()
                    .All(x => x is XElement element && typeNames.Contains(element.Name.LocalName)))
                {
                    return doc.Elements();
                }
                doc = doc.Elements().First();
            }
        }

        public static IReadOnlyDictionary<string, object> ParseRawEntity(XElement el, (string source, string target)[] mappings)
        {
            var result = new Dictionary<string, object>();
            var regularToNestedDictionary = new Dictionary<string, string>();
            foreach (var descendant in el.Elements())
            {
                var mappingsByDescendantName = mappings.Where(x => x.source == descendant.Name.LocalName);
                if (!descendant.HasElements)
                {
                    mappingsByDescendantName.ForEach(x =>
                    {
                        if (!StatisticalUnitArrayPropertyNames.Contains(x.target.Split(".", 3)[0]))
                        {
                            result.Add(x.target, descendant.Value);
                        }
                        else
                        {
                            regularToNestedDictionary.Add(descendant.Name.LocalName, descendant.Value);
                        }
                    });
                    continue;
                }

                var descendantElements = new List<KeyValuePair<string, object>>();
                string[] splittedTarget = null;
                foreach (var innerDescendant in descendant.Elements())
                {
                    var keyValueDictionary = new Dictionary<string, string>();
                  
                    foreach (var innerInnerDescendant in innerDescendant.Elements())
                    {
                        var fullPath = string.Join('.', descendant.Name.LocalName, innerDescendant.Name.LocalName,
                            innerInnerDescendant.Name.LocalName);

                        foreach (var (source, target) in mappings.Where(x => x.source == fullPath || x.target.Contains(fullPath)))
                        {
                            splittedTarget = target.Split('.', 3);

                            //checking for content in a nested dictionary
                            if (regularToNestedDictionary.TryGetValue(source, out var value) && StatisticalUnitArrayPropertyNames.Contains(target.Split(".", 3)[0]))
                            {
                                keyValueDictionary[splittedTarget.Last()] = value;
                            }
                            //usual assignment
                            else if (splittedTarget.Length > 2)
                            {
                                keyValueDictionary[splittedTarget.Last()] = innerInnerDescendant.Value;
                            }
                        }
                    }

                    if (!keyValueDictionary.Any())
                        continue;

                    if(splittedTarget != null  && splittedTarget.Length > 2)
                    {
                        descendantElements.Add(new KeyValuePair<string, object>(splittedTarget[1], keyValueDictionary));
                    }
                }
                if (splittedTarget != null && splittedTarget.Any())
                {
                    result.Add(splittedTarget[0], descendantElements);
                }
            }
            return result;
        }
            
    }
}
