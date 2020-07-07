using nscreg.Data.Entities;

namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public static void AddStatuses(NSCRegDbContext context)
        {
            context.Statuses.Add(new UnitStatus { Code = "1", Name = "Active" });
            context.Statuses.Add(new UnitStatus { Code = "2", Name = "Newly created, not yet active" });
            context.Statuses.Add(new UnitStatus { Code = "3", Name = "Dormant/Inactive" });
            context.Statuses.Add(new UnitStatus { Code = "5", Name = "Historical" });
            context.Statuses.Add(new UnitStatus { Code = "6", Name = "In liquidation phase" });
            context.Statuses.Add(new UnitStatus { Code = "7", Name = "Liquidated" });
            context.Statuses.Add(new UnitStatus { Code = "9", Name = "Unknown status" });
            context.SaveChanges();
        }
    }
}
