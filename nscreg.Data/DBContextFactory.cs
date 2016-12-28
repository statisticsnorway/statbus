using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;

namespace nscreg.Data
{
    public class DbContextFactory: IDbContextFactory<NSCRegDbContext>
    {
        public NSCRegDbContext Create(DbContextFactoryOptions options)
        {
            var builder = new DbContextOptionsBuilder<NSCRegDbContext>();
            builder.UseNpgsql("Server=localhost;Port=5432;Database=nscreg;User Id=postgres;Password=12345");
            return new NSCRegDbContext(builder.Options);
        }
    }
}
