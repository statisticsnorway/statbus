using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Common.Models.Account
{
    /// <summary>
    /// Detailed account editing model
    /// </summary>
    public class DetailsEditM
    {
        [Required, DataType(DataType.Password)]
        public string CurrentPassword { get; set; }

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
    }
}
