using System.Linq;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Services.CodeLookup
{
    public class ActivityCodeLookupStrategy : CodeLookupStrategy<ActivityCategory> 
    {
        public override IQueryable<ActivityCategory> Filter(IQueryable<ActivityCategory> query, string wildcard = null,
            string userId = null)
        {
            return userId == null
                ? query
                : query.Where(x => x.ActivityCategoryUsers.Any(u => u.UserId == userId));
        }
    }
}