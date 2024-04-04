using System.Linq;
using nscreg.Data.Entities;

namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public static void AddEnterpriseGroupRoles(NSCRegDbContext context)
        {
            if (!context.EnterpriseGroupRoles.Any())
            {
                context.EnterpriseGroupRoles.AddRange(
                    new EnterpriseGroupRole {Name = "Management/control unit", Code = "1" },
                    new EnterpriseGroupRole {Name = "Global group head (controlling unit)", Code = "2" },
                    new EnterpriseGroupRole { Name = "Global decision centre (managing unit)", Code = "3" },
                    new EnterpriseGroupRole { Name = "Highest level consolidation unit", Code = "4" },
                    new EnterpriseGroupRole { Name = "Other", Code = "5" });
                context.SaveChanges();
            }
        }
    }
}
