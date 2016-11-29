using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;

namespace nscreg.Server.Core
{
    public class CustomRoleStore : RoleStore<Role, NSCRegDbContext>
    {
        public CustomRoleStore(NSCRegDbContext context, IdentityErrorDescriber describer = null)
            : base(context, describer)
        {
        }
    }
}
