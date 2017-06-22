using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Xml.Linq;

namespace nscreg.Services.DataSources.Parsers
{
    public static class XmlHelpers
    {
        public static async Task<XContainer> LoadFile(string filePath) => await Task.Run(() => XDocument.Load(filePath));

        public static IEnumerable<XElement> GetRawEntities(XContainer doc)
            => doc.Elements().Count() > 1
                ? doc.Elements()
                : GetRawEntities(doc.Elements().First());

        public static Dictionary<string, string> ParseRawEntity(XElement el)
            => el.Descendants().ToDictionary(x => x.Name.LocalName, x => x.Value);
    }
}
