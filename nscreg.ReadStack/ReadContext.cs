using nscreg.Data;
using nscreg.Data.Entities;
using System.Linq;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace nscreg.ReadStack
{
    public class ReadContext
    {
        private readonly NSCRegDbContext _dbContext;

        public ReadContext(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        public IQueryable<Role> Roles => _dbContext.Roles.AsNoTracking();

        public IQueryable<User> Users => _dbContext.Users.AsNoTracking();

        public IQueryable<IdentityUserRole<string>> UsersRoles => _dbContext.UserRoles.AsNoTracking();

        public IQueryable<StatisticalUnit> StatUnits => _dbContext.StatisticalUnits.AsNoTracking();

        public IQueryable<LegalUnit> LegalUnits => _dbContext.LegalUnits.AsNoTracking();

        public IQueryable<LocalUnit> LocalUnits => _dbContext.LocalUnits.AsNoTracking();

        public IQueryable<EnterpriseUnit> EnterpriseUnits => _dbContext.EnterpriseUnits.AsNoTracking();

        public IQueryable<EnterpriseGroup> EnterpriseGroups => _dbContext.EnterpriseGroups.AsNoTracking();

        public IQueryable<Activity> Activities => _dbContext.Activities.AsNoTracking();
        public IQueryable<Country> Countries => _dbContext.Countries.AsNoTracking();
        public IQueryable<LegalForm> LegalForms => _dbContext.LegalForms.AsNoTracking();
        public IQueryable<SectorCode> SectorCodes => _dbContext.SectorCodes.AsNoTracking();

        public IQueryable<ActivityCategoryRole> ActivityCategoryRoles =>
            _dbContext.ActivityCategoryRoles.AsNoTracking();

        public IQueryable<ActivityCategory> ActivityCategories => _dbContext.ActivityCategories.AsNoTracking();
    }
}
