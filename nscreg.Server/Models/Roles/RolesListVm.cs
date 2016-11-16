using nscreg.Data;
using System;
using System.Collections.Generic;
using System.Linq;

namespace nscreg.Server.Models.Roles
{
    public class RolesListVm
    {
        public static RolesListVm Create(DatabaseContext db, int page, int pageSize) => new RolesListVm
        {
            Result = db.Roles.Skip(page*pageSize).Take(pageSize).Select(RoleVm.Create),
            TotalCount = db.Roles.Count(),
            TotalPages = (int) Math.Ceiling((double) db.Roles.Count()/pageSize)
        };

        public IEnumerable<RoleVm> Result { get; set; }
        public int TotalCount { get; set; }
        public int TotalPages { get; set; }
    }
}
