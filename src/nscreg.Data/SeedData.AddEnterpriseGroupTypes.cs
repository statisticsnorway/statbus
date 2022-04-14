using Microsoft.EntityFrameworkCore.Internal;
using nscreg.Data.Entities;

namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public static void AddEnterpriseGroupTypes(NSCRegDbContext context)
        {
#pragma warning disable EF1001 // Internal EF Core API usage.
            if (!context.EnterpriseGroupTypes.Any())
#pragma warning restore EF1001 // Internal EF Core API usage.
            {
                context.EnterpriseGroupTypes.AddRange(
                    new EnterpriseGroupType() { Name = "All-residents", NameLanguage1 = "Все резиденты", NameLanguage2 = "Бардык резидент", Code = "1"},
                    new EnterpriseGroupType() { Name = "Multinational domestically controlled ", NameLanguage1 = "Многонациональный внутренний контроль", NameLanguage2 = "Көп улуттуу өлкө башкарылат", Code = "2"},
                    new EnterpriseGroupType() { Name = "Multinational foreign controlled", NameLanguage1 = "Многонациональный иностранный контроль", NameLanguage2 = "Көп улуттуу чет элдик көзөмөлдө", Code = "3"});
                context.SaveChanges();
            }
        }
    }
}
