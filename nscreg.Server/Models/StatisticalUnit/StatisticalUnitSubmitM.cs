using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.ComponentModel.DataAnnotations;
using nscreg.Data.Enums;

namespace nscreg.Server.Models.StatisticalUnit
{
    public class StatisticalUnitSubmitM
    {
        [Required]
        public StatisticalUnitTypes UnitType { get; set; }
        [Required]
        public string Name { get; set; }
    }
}
