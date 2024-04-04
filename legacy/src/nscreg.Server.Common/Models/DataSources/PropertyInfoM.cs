using System.Linq;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.DataAccess;
using nscreg.Server.Common.Services;
// ReSharper disable MemberCanBePrivate.Global
// ReSharper disable UnusedAutoPropertyAccessor.Global

namespace nscreg.Server.Common.Models.DataSources
{
    /// <summary>
    /// Property Information Model
    /// </summary>
    public class PropertyInfoM
    {
        /// <summary>
        /// Property Method
        /// </summary>
        public PropertyInfoM()
        {
            LocalUnit = GetProps<LocalUnit>();
            LegalUnit = GetProps<LegalUnit>();
            EnterpriseUnit = GetProps<EnterpriseUnit>();
            EnterpriseGroup = GetProps<EnterpriseGroup>();

            DataAccessAttributeM[] GetProps<T>() where T : IStatisticalUnit =>
                DataAccessAttributesProvider<T>.CommonAttributes
                    .Concat(DataAccessAttributesProvider<T>.Attributes)
                    .Select(x =>
                    {
                        x.Name = x.Name.Split('.')[1];
                        return x;
                    })
                    .ToArray();
        }

        public DataAccessAttributeM[] LocalUnit { get; }
        public DataAccessAttributeM[] LegalUnit { get; }
        public DataAccessAttributeM[] EnterpriseUnit { get; }
        public DataAccessAttributeM[] EnterpriseGroup { get; }
    }
}
