using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using System.ComponentModel.DataAnnotations.Schema;

namespace Server.Data
{
    public class User : IdentityUser
    {
        /// <summary>
        /// Creates User object with normalized user name (UserName or Login property)
        /// </summary>
        /// <param name="login"></param>
        /// <returns></returns>
        public static User Create(string login) => new User
        {
            UserName = login,
            NormalizedUserName = login,
        };

        [NotMapped]
        public string Login
        {
            get { return UserName; }
            set
            {
                UserName = value;
                NormalizedUserName = value.ToUpper();
            }
        }

        public string Name { get; set; }
        public string Description { get; set; }
        public UserStatuses Status { get; set; }
    }
}
