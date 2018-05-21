using System.Collections.Generic;
using nscreg.Server.Common.Models.Regions;

namespace nscreg.Server.Common.Models.Users
{
    /// <summary>
    /// Вью модель списка пользователей
    /// </summary>
    public class UserListVm
    {
        /// <summary>
        /// Метод создания вью модели списка пользователей
        /// </summary>
        /// <param name="users">пользователи</param>
        /// <param name="totalCount">Общее количество</param>
        /// <param name="totalPages">Всего страниц</param>
        /// <returns></returns>
        public static UserListVm Create(IEnumerable<UserListItemVm> users, RegionNode partedRegions, int totalCount, int totalPages)
            => new UserListVm
            {
                Result = users,
                PartedRegions = partedRegions,
                TotalCount = totalCount,
                TotalPages = totalPages,
            };

        public IEnumerable<UserListItemVm> Result { get; private set; }
        public int TotalCount { get; private set; }
        public int TotalPages { get; private set; }
        public RegionNode PartedRegions { get; private set; }
    }
}
