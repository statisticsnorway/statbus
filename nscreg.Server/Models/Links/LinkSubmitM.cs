using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Server.Models.Lookup;

namespace nscreg.Server.Models.Links
{
    public class LinkSubmitM
    {
        [Required]
        public UnitSubmitM Source1 { get; set; }
        [Required]
        public UnitSubmitM Source2 { get; set; }
    }
}
