using nscreg.Data;
using nscreg.Data.Constants;
using System.Linq;
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
    }
}
