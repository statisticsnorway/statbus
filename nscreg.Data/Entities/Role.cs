using Microsoft.AspNetCore.Identity.EntityFrameworkCore;

namespace nscreg.Data.Entities
{
    public class Role : IdentityRole
    {
        public string Description { get; set; }
    }
}
