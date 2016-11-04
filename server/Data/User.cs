using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using System.ComponentModel.DataAnnotations.Schema;

namespace Server.Data
{
    public class User : IdentityUser
    {
        [NotMapped]
        public string Login
        {
            get { return UserName; }
            set { UserName = value; }
        }

        public string Name { get; set; }
        public string Description { get; set; }
        public UserStatuses Status { get; set; }
    }
}
