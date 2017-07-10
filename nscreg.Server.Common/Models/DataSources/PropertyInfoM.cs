using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.DataAccess;
using nscreg.Server.Common.Services;
// ReSharper disable MemberCanBePrivate.Global
// ReSharper disable UnusedAutoPropertyAccessor.Global

namespace nscreg.Server.Common.Models.DataSources
{
    public class PropertyInfoM
    {
        public IEnumerable<DataAccessAttributeM> LocalUnit { get; }
        public IEnumerable<DataAccessAttributeM> LegalUnit { get; }
        public IEnumerable<DataAccessAttributeM> EnterpriseUnit { get; }
        public IEnumerable<DataAccessAttributeM> EnterpriseGroup { get; }

        public PropertyInfoM()
        {
            LocalUnit = GetProps<LocalUnit>();
            LegalUnit = GetProps<LegalUnit>();
            EnterpriseUnit = GetProps<EnterpriseUnit>();
            EnterpriseGroup = GetProps<EnterpriseGroup>();

            IEnumerable<DataAccessAttributeM> GetProps<T>() where T : IStatisticalUnit
                => DataAccessAttributesProvider<T>.CommonAttributes.Concat(
                        DataAccessAttributesProvider<T>.Attributes)
                    .Select(x =>
                    {
                        x.Name = x.Name.Split('.')[1];
                        return x;
                    });
        }
    }
}
