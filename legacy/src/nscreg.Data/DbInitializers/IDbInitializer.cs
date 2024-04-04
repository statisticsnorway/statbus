using nscreg.Utilities.Configuration;

namespace nscreg.Data.DbInitializers
{
    public interface IDbInitializer
    {
        void Initialize(NSCRegDbContext context, ReportingSettings reportingSettings = null);
    }
}
