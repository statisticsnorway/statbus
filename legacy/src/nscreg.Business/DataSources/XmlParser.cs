using System;
using System.Collections.Generic;
using System.Linq;
using System.Xml.Linq;
using nscreg.Data.Constants;
using nscreg.Utilities.Extensions;

namespace nscreg.Business.DataSources
{
    public static class XmlParser
    {

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
                doc = doc.Elements().FirstOrDefault() ?? throw new Exception("XML file is invalid");
            }
        }

        public static IReadOnlyDictionary<string, object> ParseRawEntity(XElement el, (string source, string target)[] mappings, int skipCount = 0)
        {
            var result = new Dictionary<string, object>();
            var regularToNestedDictionary = new Dictionary<string, string>();
            foreach (var descendant in el.Elements().Skip(skipCount))
            {
                if (!descendant.HasElements)
                {
                    var mappingsByDescendantName = mappings.Where(x => x.source == descendant.Name.LocalName);
                    mappingsByDescendantName.ForEach(x =>
                    {
                        if (!StatUnitKeyValueParser.StatisticalUnitArrayPropertyNames.Contains(x.target.Split(".", 2)[0]))
                        {
                            result.Add(x.target, descendant.Value);
                        }
                        else
                        {
                            regularToNestedDictionary.Add(x.source, descendant.Value);
                        }
                    });
                    continue;
                }

                var descendantElements = new List<KeyValuePair<string, Dictionary<string,string>>>();
                string[] splittedTarget = null;
                foreach (var innerDescendant in descendant.Elements())
                {
                    var keyValueDictionary = new Dictionary<string, string>();
                  
                    foreach (var innerInnerDescendant in innerDescendant.Elements())
                    {
                        var fullPath = string.Join('.', descendant.Name.LocalName.Trim(), innerDescendant.Name.LocalName.Trim(),
                            innerInnerDescendant.Name.LocalName.Trim());
                        foreach (var (source, target) in mappings.Where(x => x.source == fullPath || regularToNestedDictionary.ContainsKey(x.source)))
                        {
                            splittedTarget = target.Split('.', 3);
                            //usual assignment
                            if (splittedTarget.Length <= 2)
                                continue;

                            //checking for content in a nested dictionary
                            if (regularToNestedDictionary.TryGetValue(source, out var value) && StatUnitKeyValueParser.StatisticalUnitArrayPropertyNames.Contains(splittedTarget[0]))
                            {
                                keyValueDictionary[splittedTarget.Last()] = value;
                                continue;
                            }

                            keyValueDictionary[splittedTarget.Last()] = innerInnerDescendant.Value;

                        }
                    }

                    if (!keyValueDictionary.Any())
                        continue;

                    if(splittedTarget != null  && splittedTarget.Length > 2)
                    {
                        descendantElements.Add(new KeyValuePair<string, Dictionary<string,string>>(splittedTarget[1], keyValueDictionary));
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
