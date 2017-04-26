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
        [Required, DataType(DataType.Text)]
        public string Name { get; set; }

        [Required, DataType(DataType.Text)]
        public string Code { get; set; }

        [Required, DataType(DataType.Text)]
        public string AdminstrativeCenter { get; set; }
    }
}
