using nscreg.Data.Entities;

namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public static void AddStatuses(NSCRegDbContext context)
        {
            context.UnitStatuses.Add(new UnitStatus {Code = "1", Name = "Unit is active"});
            context.UnitStatuses.Add(new UnitStatus { Code = "2", Name = "Unit is not active (inactive)" });
            context.UnitStatuses.Add(new UnitStatus { Code = "3", Name = "Newly created statistical unit. Not yet active" });
            context.UnitStatuses.Add(new UnitStatus { Code = "4", Name = "The unit is in liquidation phase" });
            context.UnitStatuses.Add(new UnitStatus { Code = "5", Name = "Unit liquidated" });
            context.UnitStatuses.Add(new UnitStatus { Code = "0", Name = "There is no information about the unit" });
            context.SaveChanges();
        }
    }
}
