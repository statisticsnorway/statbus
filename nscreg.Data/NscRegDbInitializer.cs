using Microsoft.EntityFrameworkCore;
using System.Linq;
using nscreg.Data.Entities;

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
            if (!context.Regions.Any()) SeedData.AddRegions(context);

            if (!context.ActivityCategories.Any()) SeedData.AddActivityCategories(context);

            if (!context.LegalForms.Any())
            {
                context.LegalForms.Add(new LegalForm {Name = "Хозяйственные товарищества и общества"});
                context.SaveChanges();
                var ff = context.LegalForms
                    .Where(x => x.Name == "Хозяйственные товарищества и общества")
                    .Select(x => x.Id)
                    .SingleOrDefault();
                context.LegalForms.AddRange(new LegalForm {Name = "Акционерное общество", ParentId = ff});
                context.SaveChanges();
            }

            if (!context.SectorCodes.Any()) SeedData.AddSectorCodes(context);

            SeedData.AddUsersAndRoles(context);

            if (!context.StatisticalUnits.Any()) SeedData.AddStatUnits(context);

            if (!context.DataSources.Any()) SeedData.AddDataSources(context);

            if (!context.LegalForms.Any()) SeedData.AddLegalForms(context);

            if (!context.Countries.Any()) SeedData.AddCountries(context);
        }
    }
}
