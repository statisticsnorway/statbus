using System.Collections.Generic;
using System.Linq;
using System.Xml.Linq;

namespace nscreg.Business.DataSources
{
    public static class XmlParser
    {
        public static IEnumerable<XElement> GetRawEntities(XContainer doc)
        {
            while (true)
            {
                if (doc.Elements().Count() > 1) return doc.Elements();
                doc = doc.Elements().First();
            }
        }

        public static IReadOnlyDictionary<string, string> ParseRawEntity(XElement el)
            => el.Descendants().ToDictionary(x => x.Name.LocalName, x => x.Value);
    }
}
