using System.Collections.Generic;
using System.IO;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;

namespace nscreg.Server.DataUploadSvc
{
    public static class DbContextHelper
    {
        public static NSCRegDbContext CreateDbContext(string connectionString)
        {
            var builder = new DbContextOptionsBuilder<NSCRegDbContext>();
            builder.UseNpgsql(connectionString);
            return new NSCRegDbContext(builder.Options);
        }

        public static NSCRegDbContext CreateInMemoryContext()
        {
            var builder = new DbContextOptionsBuilder<NSCRegDbContext>();
            builder.UseInMemoryDatabase();
            return new NSCRegDbContext(builder.Options);
        }

        public static void SeedInMemoryData(NSCRegDbContext ctx)
        {
            var admin42 = new User {Name = "admin42"};
            ctx.Users.Add(admin42);
            ctx.SaveChanges();
            ctx.DataSources.Add(new DataSource
            {
                DataSourceQueuedUploads = new List<DataSourceQueue>
                {
                    new DataSourceQueue
                    {
                        DataSourceFileName = "LIK_13092016.xml",
                        DataSourcePath = Directory.GetCurrentDirectory(),
                        Status = DataSourceQueueStatuses.InQueue,
                        User = admin42,
                    },
                },
                AllowedOperations = DataSourceAllowedOperation.CreateAndAlter,
                AttributesToCheck = "NscCode,Tin,FullName",
                Name = "LIK?",
                Priority = DataSourcePriority.Trusted,
                StatUnitType = StatUnitTypes.EnterpriseUnit,
                VariablesMapping = "NscCode-StatId,FullName-Name,Tin-TaxRegId",
                User = admin42,
            });
            ctx.SaveChanges();
        }
    }
}
