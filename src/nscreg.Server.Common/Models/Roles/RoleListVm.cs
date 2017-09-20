using System.Collections.Generic;

namespace nscreg.Server.Common.Models.Roles
{
    /// <summary>
    /// Вью модель списка ролей
    /// </summary>
    public class RoleListVm
    {
        /// <summary>
        /// Метод создания вью модели списка ролей
        /// </summary>
        /// <param name="roles">Роли</param>
        /// <param name="totalCount">Общее количество</param>
        /// <param name="totalPages">Всего страниц</param>
        /// <returns></returns>
        public static RoleListVm Create(IEnumerable<RoleVm> roles, int totalCount, int totalPages) =>
            new RoleListVm
            {
                Result = roles,
                TotalCount = totalCount,
                TotalPages = totalPages,
            };

        public IEnumerable<RoleVm> Result { get; private set; }
        public int TotalCount { get; private set; }
        public int TotalPages { get; private set; }
    }
}
