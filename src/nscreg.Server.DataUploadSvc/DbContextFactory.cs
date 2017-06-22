using Microsoft.EntityFrameworkCore;
using nscreg.Data;

namespace nscreg.Server.DataUploadSvc
{
    public static class DbContextFactory
    {
        public static NSCRegDbContext Create(string connectionString)
        {
            var builder = new DbContextOptionsBuilder<NSCRegDbContext>();
            builder.UseNpgsql(connectionString);
            return new NSCRegDbContext(builder.Options);
        }

        public static NSCRegDbContext CreateInMemory()
        {
            var builder = new DbContextOptionsBuilder<NSCRegDbContext>();
            builder.UseInMemoryDatabase();
            return new NSCRegDbContext(builder.Options);
        }
    }
}
