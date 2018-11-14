using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Common.Models.Lookup
{
    /// <summary>
    /// Вью модель поиска кода
    /// </summary>
    public class CodeLookupVm
    {
        public int Id { get; set; }
        [Required]
        public string Code { get; set; }
        public string Name { get; set; }
        public string NameLanguage1 { get; set; }
        public string NameLanguage2 { get; set; }
    }
}
