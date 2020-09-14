using System;
using System.Collections.Generic;
using System.Linq;
using System.Xml.Linq;
using nscreg.Data.Constants;

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
                doc = doc.Elements().First();
            }
        }

        public static IReadOnlyDictionary<string, object> ParseRawEntity(XElement el, (string source, string target)[] mappings)
        {
            // for properties which have array type. Example of structure
            // Activities -> Activity -> Code : "some code"
            //                        -> Category : "some  another code"
            //            -> Activity -> Code : "some code"
            //                        -> Category : "some  another code"
            var result = new Dictionary<string, object>();

                foreach (var descendant in el.Elements())
                {
                    var targetMappingName = mappings.FirstOrDefault(x => x.source.Contains(descendant.Name.LocalName)).target;
                    if (!descendant.HasElements)
                    {
                        result.Add(targetMappingName.Split('.', 3).Last(), descendant.Value);
                        continue;
                    }

                    var descendantElements = new List<KeyValuePair<string, object>>();

                    foreach (var innerDescendant in descendant.Elements())
                    {

                        var array = new Dictionary<string, string>();

                        foreach (var innerInnerDescendant in innerDescendant.Elements())
                        {
                            var fullPath = string.Join('.', descendant.Name.LocalName, innerDescendant.Name.LocalName,
                                innerInnerDescendant.Name.LocalName);
                            foreach (var (source, target) in mappings)
                            {
                                if (fullPath == source)
                                {
                                    array[target.Split('.', 3).Last()] = innerInnerDescendant.Value;
                                }
                            }
                        }

                        var sourceMappingName = mappings
                            .FirstOrDefault(x => x.source.Contains(string.Join('.', descendant.Name.LocalName, innerDescendant.Name.LocalName))).target;

                            descendantElements.Add(new KeyValuePair<string, object>(sourceMappingName.Split('.')[1], array));
                    }
                    result.Add(targetMappingName.Split('.')[0], descendantElements);
                }
            
            return result;
        }
            
    }
}
