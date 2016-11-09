using Microsoft.AspNetCore.Identity.EntityFrameworkCore;

namespace Server.Data
{
    public class Role : IdentityRole
    {
        /// <summary>
        /// Creates Role object with normalized name
        /// </summary>
        /// <param name="name"></param>
        /// <param name="description"></param>
        /// <returns></returns>
        public static Role Create(string name, string description = null) => new Role
        {
            Name = name,
            NormalizedName = name.ToUpper(),
            Description = description
        };

        public string Description { get; set; }
    }
}
