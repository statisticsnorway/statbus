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
                    .All(x => x is XElement && typeNames.Contains(((XElement) x).Name.LocalName)))
                {
                    return doc.Elements();
                }
                doc = doc.Elements().First();
            }
        }

        public static IReadOnlyDictionary<string, string> ParseRawEntity(XElement el)
            => el.Descendants().ToDictionary(x => x.Name.LocalName, x => x.Value);
    }
}
