using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using Server.Data;

namespace Server.Models.Users
{
    public class UserSubmitM
    {
        [Required]
        public string Login { get; set; }

        [Required, DataType(DataType.Password)]
        public string Password { get; set; }

        [Required, DataType(DataType.Password), Compare(nameof(Password))]
        public string ConfirmPassword { get; set; }

        [Required]
        public string Name { get; set; }

        [DataType(DataType.PhoneNumber)]
        public string Phone { get; set; }

        [DataType(DataType.EmailAddress)]
        public string Email { get; set; }

        public UserStatus Status { get; set; }
        public IEnumerable<string> AssignedRoles { get; set; }
        public string Description { get; set; }
    }
}
