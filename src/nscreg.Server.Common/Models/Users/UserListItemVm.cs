using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using nscreg.Data.Constants;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.Users
{
    /// <summary>
    /// Вью модель списка едениц пользователей
    /// </summary>
    public class UserListItemVm
    {
        /// <summary>
        /// Метод создания вью модели списка едениц пользователей
        /// </summary>
        public static readonly Expression<Func<User, UserListItemVm>> Creator =
            user => new UserListItemVm
            {
                Id = user.Id,
                Name = user.Name,
                Description = user.Description,
                Status = user.Status,
                CreationDate = user.CreationDate,
                SuspensionDate = user.SuspensionDate,
                Regions = user.UserRegions.Select(x => x.Region.Id).ToArray()
            };

        public string Id { get; private set; }
        public string Name { get; private set; }
        public string Description { get; private set; }
        public UserStatuses Status { get; private set; }
        public DateTime CreationDate { get; private set; }
        public DateTime? SuspensionDate { get; private set; }
        public List<UserRoleVm> Roles { get; set; }
        public int[] Regions { get; set; }
    }
}
