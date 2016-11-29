using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;

namespace nscreg.Server.Core
{
    public class CustomUserStore : UserStore<User, Role, NSCRegDbContext>
    {
        public CustomUserStore(NSCRegDbContext context, IdentityErrorDescriber describer = null)
            : base(context, describer)
        {
        }
    }
}
