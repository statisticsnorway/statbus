using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Models.Lookup
{
    public class CodeLookupVm
    {
        public int Id { get; set; }
        [Required]
        public string Code { get; set; }
        public string Name { get; set; }
    }
}
