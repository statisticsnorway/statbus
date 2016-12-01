using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Models.Roles
{
    public class RoleSubmitM
    {
        [Required]
        public string Name { get; set; }

        public string Description { get; set; }

        [Required]
        public IEnumerable<int> AccessToSystemFunctions { get; set; }

        [Required]
        public IEnumerable<string> StandardDataAccess { get; set; }
    }
}
