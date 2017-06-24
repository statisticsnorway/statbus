using System.Collections.Generic;

namespace nscreg.Server.Common.Models.Users
{
    public interface IUserSubmit
    {
        IEnumerable<int> UserRegions { get; set; }
    }
}
