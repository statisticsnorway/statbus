using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.Account
{
    /// <summary>
    /// Detailed View Account Model
    /// </summary>
    public class DetailsVm
    {
        public static DetailsVm Create(User user) => new DetailsVm
        {
            Name = user.Name,
            Phone = user.PhoneNumber,
            Email = user.Email
        };

        public string Name { get; private set; }
        public string Phone { get; private set; }
        public string Email { get; private set; }
    }
}
