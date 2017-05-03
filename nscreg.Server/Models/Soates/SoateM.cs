using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Resources.Languages;

namespace nscreg.Server.Models.Soates
{
    public class SoateM
    {
        [Required, DataType(DataType.Text), MinLength(1), MaxLength(75)]
        public string Name { get; set; }

        [Required, DataType(DataType.Text), MinLength(1), MaxLength(14)]
        [RegularExpression("([0-9]*)")]
        public string Code { get; set; }

        [DataType(DataType.Text), MaxLength(75)]
        public string AdminstrativeCenter { get; set; }
    }
}
