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
                    .All(x => x is XElement && typeNames.Contains(((XElement) x).Name.LocalName)))
                {
                    return doc.Elements();
                }
                doc = doc.Elements().First();
            }
        }

        public static IReadOnlyDictionary<string, object> ParseRawEntity(XElement el)
        {
            var result = new Dictionary<string, object> ();
            foreach (var descendant in el.Elements())
            {
                if (descendant.Elements().Any())
                {
                    var elem = new List<KeyValuePair<string, Dictionary<string, string>>>();
                    foreach (var innerDescendant in descendant.Elements())
                    {
                        var list = innerDescendant.Elements().ToDictionary(x=>x.Name.LocalName, x=>x.Value);
                        elem.Add(new KeyValuePair<string, Dictionary<string,string>>(innerDescendant.Name.LocalName, list));
                    }
                    result.Add(descendant.Name.LocalName, elem);
                }
                else
                {
                    result.Add(descendant.Name.LocalName, descendant.Value);
                }
            }
            return result;
        }
            
    }
}
