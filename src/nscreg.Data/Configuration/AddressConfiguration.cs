using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using nscreg.Data.Core.EntityConfiguration;
using nscreg.Data.Entities;

namespace nscreg.Data.Configuration
{
    /// <summary>
    /// Address Configuration Class
    /// </summary>
    public class AddressConfiguration : EntityTypeConfigurationBase<Address>
    {
        public override void Configure(EntityTypeBuilder<Address> builder)
        {
            builder.HasKey(x => x.Id);
            SetColumnNames(builder);
        }

        /// <summary>
        /// Column Name Setting Method
        /// </summary>
        private static void SetColumnNames(EntityTypeBuilder<Address> builder)
        {
            builder.HasIndex(x => new
            {
                x.AddressPart1,
                x.AddressPart2,
                x.AddressPart3,
                x.RegionId,
                x.Latitude,
                x.Longitude
            });
        }
    }
}
