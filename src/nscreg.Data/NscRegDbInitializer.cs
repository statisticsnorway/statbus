using System;
using Microsoft.EntityFrameworkCore;
using System.Linq;
using nscreg.Data.DbInitializers;
using nscreg.Data.Entities;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Enums;

namespace nscreg.Data
{
    /// <summary>
    /// Класс инициализации данных в БД
    /// </summary>
    public static class NscRegDbInitializer
    {
        /// <summary>
        /// Drop database if exists and create new one, then apply migrations
        /// </summary>
        /// <param name="context"></param>
        public static void RecreateDb(NSCRegDbContext context)
        {
            context.Database.EnsureDeleted();
            context.Database.Migrate();
        }
        
        /// <summary>
        /// Drop and re-create statunit search view
        /// </summary>
        /// <param name="context"></param>
        /// <param name="provider"></param>
        public static void CreateViewsProceduresAndFunctions(NSCRegDbContext context, ConnectionProvider provider, ReportingSettings reportingSettings = null)
        {
            IDbInitializer initializer;

            switch (provider)
            {
                case ConnectionProvider.InMemory: initializer = new InMemoryDbInitializer();
                    break;
                case ConnectionProvider.SqlServer: initializer = new MsSqlDbInitializer();
                    break;
                case ConnectionProvider.PostgreSql: initializer = new PostgreSqlDbInitializer();
                    break;
                default: throw new Exception(Resources.Languages.Resource.ProviderIsNotSet);
            }

            initializer.Initialize(context, reportingSettings);
        }

        /// <summary>
        /// Add or ensure System Administrator role and its access rules
        /// </summary>
        /// <param name="context"></param>
        public static void EnsureRoles(NSCRegDbContext context) => SeedData.AddUsersAndRoles(context);

        /// <summary>
        /// Метод инициализации данных в БД
        /// </summary>
        /// <param name="context"></param>
        public static void Seed(NSCRegDbContext context)
        {
            if (!context.Regions.Any()) SeedData.AddRegions(context);

            if (!context.ActivityCategories.Any()) SeedData.AddActivityCategories(context);

            if (!context.LegalForms.Any())
            {
                context.LegalForms.Add(new LegalForm {Name = "Хозяйственные товарищества и общества"});
                context.SaveChanges();
                var lf = context.LegalForms
                    .Where(x => x.Name == "Хозяйственные товарищества и общества")
                    .Select(x => x.Id)
                    .SingleOrDefault();
                context.LegalForms.AddRange(new LegalForm {Name = "Акционерное общество", ParentId = lf});
                context.SaveChanges();
            }

            if (!context.SectorCodes.Any()) SeedData.AddSectorCodes(context);

            if (!context.StatisticalUnits.Any()) SeedData.AddStatUnits(context);

            if (!context.DataSources.Any()) SeedData.AddDataSources(context);

            if (!context.LegalForms.Any()) SeedData.AddLegalForms(context);

            if (!context.Countries.Any()) SeedData.AddCountries(context);

            if (!context.AnalysisLogs.Any()) SeedData.AddAnalysisLogs(context);
        }
    }
}
