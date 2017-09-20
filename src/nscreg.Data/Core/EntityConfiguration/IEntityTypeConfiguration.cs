using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace nscreg.Data.Core.EntityConfiguration
{
    public interface IEntityTypeConfiguration
    {
        void Configure(ModelBuilder builder);
    }

    public interface IEntityTypeConfiguration<T> : IEntityTypeConfiguration where T : class
    {
        void Configure(EntityTypeBuilder<T> builder);
    }
}
