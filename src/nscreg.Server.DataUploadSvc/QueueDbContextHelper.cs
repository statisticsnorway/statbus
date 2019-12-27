using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using System.Collections.Generic;
using System.IO;

namespace nscreg.Server.DataUploadSvc
{
    /// <summary>
    /// DB context queue helper class
    /// </summary>
    internal static class QueueDbContextHelper
    {
        /// <summary>
        /// Setting the initial data in RAM
        /// </summary>
        /// <param name = "ctx"> Context </param>
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
                        DataSourcePath = Path.Combine(Directory.GetCurrentDirectory(), "LIK_13092016.xml"),
                        Status = DataSourceQueueStatuses.InQueue,
                        User = admin42,
                    },
                    new DataSourceQueue
                    {
                        DataSourceFileName = "LIK_13092017.xml",
                        DataSourcePath = Path.Combine(Directory.GetCurrentDirectory(), "LIK_13092017.xml"),
                        Status = DataSourceQueueStatuses.InQueue,
                        User = admin42,
                    },
                },
                AllowedOperations = DataSourceAllowedOperation.CreateAndAlter,
                AttributesToCheck = "NscCode,Tin,FullName",
                Name = "test data source template",
                Priority = DataSourcePriority.Trusted,
                StatUnitType = StatUnitTypes.LocalUnit,
                VariablesMapping = "NscCode-StatId,FullName-Name",
                User = admin42,
            });
            ctx.SaveChanges();
        }
    }
}
