using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.DataAccess;
using nscreg.Utilities.Attributes;

namespace nscreg.Server.Common.Models.Users
{
    /// <summary>
    /// User Editing Model
    /// </summary>
    public class UserEditM : IUserSubmit
    {
        [Required, PrintableString]
        public string Login { get; set; }

        [DataType(DataType.Password)]
        public string NewPassword { get; set; }

        [DataType(DataType.Password), Compare(nameof(NewPassword))]
        public string ConfirmPassword { get; set; }

        [Required]
        public string Name { get; set; }

        [DataType(DataType.PhoneNumber)]
        public string Phone { get; set; }

        [DataType(DataType.EmailAddress)]
        public string Email { get; set; }

        [Required]
        public string AssignedRole { get; set; }

        public string Description { get; set; }

        public UserStatuses? Status { get; set; }

        public DataAccessModel DataAccess { get; set; }

        [Required]
        public IEnumerable<int> UserRegions { get; set; }

        [Required]
        public IEnumerable<int> ActivityCategoryIds { get; set; }

        public bool IsAllActivitiesSelected { get; set; }

    }
}
