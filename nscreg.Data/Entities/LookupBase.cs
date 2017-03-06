using System.Globalization;

namespace nscreg.Data.Entities
{
    public abstract class LookupBase
    {
        public int Id { get; set; }
        public string NameRu { get; set; }
        public string NameKg { get; set; }
        public string NameEn { get; set; }
    }
}