using System;
using nscreg.Data;
using nscreg.Data.Constants;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Data.Entities;

namespace nscreg.CommandStack
{
    public class CommandContext
    {
        private readonly NSCRegDbContext _dbContext;

        public CommandContext(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        #region ROLES

        public void CreateRole(Role role)
        {
            _dbContext.Roles.Add(role);
            _dbContext.SaveChanges();
        }

        public void UpdateRole(Role role)
        {
            _dbContext.Roles.Update(role);
            _dbContext.SaveChanges();
        }

        public void SuspendRole(string id)
        {
            _dbContext.Roles.FirstOrDefault(x => x.Id == id).Status = RoleStatuses.Suspended;
            _dbContext.SaveChanges();
        }

        #endregion

        #region USERS

        public async Task SetUserStatus (string id, UserStatuses status)
        {
            var user = _dbContext.Users.Single(x => x.Id == id);
            user.Status = status;
            user.SuspensionDate = status == UserStatuses.Suspended ? DateTime.Now : (DateTime?)null;
            await _dbContext.SaveChangesAsync();
        }

        #endregion

    }
}
