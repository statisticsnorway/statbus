using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using nscreg.Data.Constants;
using nscreg.Utilities;

namespace nscreg.Server.Models.Users
{
    public class UserEditM
    {
        [Required]
        public string Login { get; set; }

        [DataType(DataType.Password)]
        public string NewPassword { get; set; }

        [DataType(DataType.Password), Compare(nameof(NewPassword))]
        public string ConfirmPassword { get; set; }

        [Required, PrintableString]
        public string Name { get; set; }

        [DataType(DataType.PhoneNumber)]
        public string Phone { get; set; }

        [DataType(DataType.EmailAddress)]
        public string Email { get; set; }

        public UserStatuses Status { get; set; }

        [Required]
        public IEnumerable<string> AssignedRoles { get; set; }

        public string Description { get; set; }

        [Required]
        public IEnumerable<int> DataAccess { get; set; }
    }
}
