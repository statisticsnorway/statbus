using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;

namespace nscreg.Data.Entities
{
    public class Role : IdentityRole
    {
        public string Description { get; set; }
        public string AccessToSystemFunctions { get; set; }

        [NotMapped]
        public IEnumerable<int> AccessToSystemFunctionsArray
        {
            get
            {
                return AccessToSystemFunctions.Split(',').Select(x => int.Parse(x));
            }
            set
            {
                AccessToSystemFunctions = string.Join(",", value);
            }
        }
    }
}
