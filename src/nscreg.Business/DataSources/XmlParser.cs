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
            var result = new Dictionary<string, object>();

            var unit = el.Elements().ToDictionary(x => x.Name.LocalName, x => x.Value).Join(mappings, r => r.Key, m => m.source, (r, m) => new KeyValuePair<string, object>(m.target, r.Value));

            foreach (var descendant in el.Elements())
            {
                if (!descendant.HasElements) continue;

                // for properties which have array type. Example of structure
                // Activities -> Activity -> Code : "some code"
                //                        -> Category : "some  another code"
                //            -> Activity -> Code : "some code"
                //                        -> Category : "some  another code"

                var elem = new List<KeyValuePair<string, object>>();
                foreach (var innerDescendant in descendant.Elements())
                {
                    var list = innerDescendant.Elements().ToDictionary(x => x.Name.LocalName, x => x.Value);

                    elem.Add(new KeyValuePair<string, object>(mappings.FirstOrDefault(x => x.source == innerDescendant.Name.LocalName).target, list));
                }
            }
            return result;
        }
            
    }
}
