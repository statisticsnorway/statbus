using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using Newtonsoft.Json;

// ReSharper disable once CheckNamespace
namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public static void AddDataSources(NSCRegDbContext context)
        {
            var ds1 = new DataSource
            {
                Name = "data source #1",
                Description = "data source #1 detailed description",
                Priority = DataSourcePriority.Ok,
                StatUnitType = StatUnitTypes.LegalUnit,
                Restrictions = null,
                VariablesMapping = "id-RegId,name-Name",
                AttributesToCheck = "id,name,something",
                AllowedOperations = DataSourceAllowedOperation.CreateAndAlter,
                CsvDelimiter = ",",
                CsvSkipCount = 0,
            };
            var ds2 = new DataSource
            {
                Name = "data source #2",
                Description = "data source #2 detailed description",
                Priority = DataSourcePriority.Trusted,
                StatUnitType = StatUnitTypes.LocalUnit,
                Restrictions = null,
                VariablesMapping = "id-RegId,whatever-Name",
                AttributesToCheck = "id,salary,whatever",
                AllowedOperations = DataSourceAllowedOperation.Create,
                CsvDelimiter = ",",
                CsvSkipCount = 0,
            };

            context.DataSources.AddRange(ds1, ds2);
            context.SaveChanges();

            var dsq1 = new DataSourceQueue
            {
                DataSource = ds1,
                DataSourceFileName = "qwe.xml",
                DataSourcePath = ".\\",
                DataUploadingLogs = new[]
                {
                    new DataUploadingLog
                    {
                        StartImportDate = DateTimeOffset.Now,
                        EndImportDate = DateTimeOffset.Now,
                        StatUnitName = "qwe",
                        SerializedUnit =
                            JsonConvert.SerializeObject(new LegalUnit {Name = "42", DataSource = "qwe.xml"}),
                        Status = DataUploadingLogStatuses.Warning,
                        Errors = JsonConvert.SerializeObject(
                            new Dictionary<string, string[]> {[nameof(LegalUnit.UnitStatusId)] = new[] {"err1", "err2"}}),
                    }
                },
                EndImportDate = DateTimeOffset.Now,
                StartImportDate = DateTimeOffset.Now,
                User = context.Users.FirstOrDefault(),
                Status = DataSourceQueueStatuses.DataLoadCompletedPartially,
            };

            context.DataSourceQueues.Add(dsq1);
            context.SaveChanges();
        }
    }
}
