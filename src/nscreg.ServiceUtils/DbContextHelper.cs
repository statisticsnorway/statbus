using Microsoft.EntityFrameworkCore;
using nscreg.Data;

namespace nscreg.ServicesUtils
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
    }
}
