using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using nscreg.Data.Constants;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;

namespace nscreg.Data.Entities
{
    public class Role : IdentityRole
    {
        public string Description { get; set; }
        public string AccessToSystemFunctions { get; set; }
        public string StandardDataAccess { get; set; }
        public RoleStatuses Status { get; set; }

        [NotMapped]
        public IEnumerable<int> AccessToSystemFunctionsArray
        {
            get
            {
                return string.IsNullOrEmpty(AccessToSystemFunctions)
                    ? new int[0]
                    : AccessToSystemFunctions.Split(',').Select(int.Parse);
            }
            set
            {
                AccessToSystemFunctions = string.Join(",", value);
            }
        }

        [NotMapped]
        public IEnumerable<string> StandardDataAccessArray
        {
            get
            {
                return string.IsNullOrEmpty(StandardDataAccess)
                    ? new string[0]
                    : StandardDataAccess.Split(',');
            }
            set
            {
                StandardDataAccess = string.Join(",", value);
            }
        }
    }
}
