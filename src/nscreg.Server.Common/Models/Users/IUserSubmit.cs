using System.Collections.Generic;

namespace nscreg.Server.Common.Models.Users
{
    /// <summary>
    /// Модель отправки пользователя
    /// </summary>
    public interface IUserSubmit
    {
        IEnumerable<int> UserRegions { get; set; }
        IEnumerable<int> ActiviyCategoryIds { get; set; }
        bool IsAllActivitiesSelected { get; set; }
    }
}
