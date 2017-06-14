using Microsoft.EntityFrameworkCore;
using System.Linq;

namespace nscreg.Data
{
    public static class NscRegDbInitializer
    {
        public static void RecreateDb(NSCRegDbContext context)
        {
            context.Database.EnsureDeleted();
            context.Database.Migrate();
        }

        public static void Seed(NSCRegDbContext context)
        {
            if (!context.Regions.Any())
            {
                SeedData.AddRegions(context);
                context.SaveChanges();
            }

            if (!context.ActivityCategories.Any())
            {
                SeedData.AddActivityCategories(context);
                context.SaveChanges();
            }

            SeedData.AddUsersAndRoles(context);
            context.SaveChanges();

            if (!context.StatisticalUnits.Any())
            {
                SeedData.AddStatUnits(context);
                context.SaveChanges();
            }

            if (!context.DataSources.Any())
            {
                SeedData.AddDataSources(context);
                context.SaveChanges();
            }
        }
    }
}
