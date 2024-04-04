using System.Collections.Generic;

namespace nscreg.Server.Common.Models.Users
{
    /// <summary>
    ///User Submission Model
    /// </summary>
    public interface IUserSubmit
    {
        IEnumerable<int> UserRegions { get; set; }
        IEnumerable<int> ActivityCategoryIds { get; set; }
        bool IsAllActivitiesSelected { get; set; }
    }
}
