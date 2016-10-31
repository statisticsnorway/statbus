using System.Runtime.Serialization;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;

namespace Server.Data
{
    public class User : IdentityUser
    {
        [IgnoreDataMember]
        public string Login
        {
            get { return UserName; }
            set { UserName = value; }
        }

        public string Name { get; set; }
        public string Description { get; set; }
        public UserStatus Status { get; set; }
    }
}
