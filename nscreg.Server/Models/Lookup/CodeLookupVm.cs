using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Models.Lookup
{
    public class CodeLookupVm
    {
        [Required]
        public string Code { get; set; }
        public string Name { get; set; }
    }
}
