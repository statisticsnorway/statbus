using nscreg.Data.Constants;
using nscreg.Data.Entities;

// ReSharper disable once CheckNamespace
namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public static void AddLegalForms(NSCRegDbContext context)
        {
            context.DataSources.AddRange(
                new DataSource
                {
                    Name = "data source #1",
                    Description = "data source #1 detailed description",
                    Priority = DataSourcePriority.Ok,
                    StatUnitType = (StatUnitTypes) 1,
                    Restrictions = null,
                    VariablesMapping = "123",
                    AttributesToCheck = "id,name,something",
                    AllowedOperations = DataSourceAllowedOperation.CreateAndAlter,
                },
                new DataSource
                {
                    Name = "data source #2",
                    Description = "data source #2 detailed description",
                    Priority = DataSourcePriority.Trusted,
                    StatUnitType = (StatUnitTypes) 2,
                    Restrictions = null,
                    VariablesMapping = "234",
                    AttributesToCheck = "id,salary,whatever",
                    AllowedOperations = DataSourceAllowedOperation.Create,
                });

            context.SaveChanges();
        }
    }
}
