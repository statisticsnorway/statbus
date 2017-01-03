using Microsoft.EntityFrameworkCore;
using nscreg.Data;

namespace nscreg.Server.Test
{
    public class InMemoryDb
    {
        public InMemoryDb()
        {
            GetContext = new NSCRegDbContext(new DbContextOptionsBuilder<NSCRegDbContext>().UseInMemoryDatabase().Options);
        }

        public NSCRegDbContext GetContext { get; }
    }
}
