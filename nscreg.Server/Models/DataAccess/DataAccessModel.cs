using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using AutoMapper;
using Microsoft.EntityFrameworkCore.Internal;
using nscreg.Data.Entities;
using nscreg.Server.Services;

namespace nscreg.Server.Models.DataAccess
{
    public class DataAccessModel
    {
        public List<DataAccessAttributeVm> EnterpriseGroup { get; set; }
        public List<DataAccessAttributeVm> EnterpriseUnit { get; set; }
        public List<DataAccessAttributeVm> LegalUnit { get; set; }
        public List<DataAccessAttributeVm> LocalUnit { get; set; }

        public IEnumerable<string> ToStringCollection()
        {
            return LegalUnit.Concat(LocalUnit)
                .Concat(EnterpriseUnit)
                .Concat(EnterpriseGroup)
                .Where(v => v.Allowed)
                .Select(v => v.Name);
        }

        public override string ToString()
        {
            return ToStringCollection().Join(",");
        }

        public static DataAccessModel FromString(string dataAccess = null)
        {
            var dataAccessCollection = (dataAccess ?? "").Split(',').ToImmutableHashSet();
            return new DataAccessModel
            {
                LocalUnit = GetDataAccessAttributes<LocalUnit>(dataAccessCollection),
                LegalUnit = GetDataAccessAttributes<LegalUnit>(dataAccessCollection),
                EnterpriseUnit = GetDataAccessAttributes<EnterpriseUnit>(dataAccessCollection),
                EnterpriseGroup = GetDataAccessAttributes<EnterpriseGroup>(dataAccessCollection),
            };
        }

        private static List<DataAccessAttributeVm> GetDataAccessAttributes<T>(ISet<string> dataAccess) where T: IStatisticalUnit
        {
            return DataAcessAttributesProvider<T>.List().Select(v => Mapper.Map(v, new DataAccessAttributeVm()
            {
                Allowed = dataAccess.Contains(v.Name)
            })).ToList();
        }

        public bool IsAllowedInAllTypes(string propName)
        {
            throw new NotImplementedException();
            return LegalUnit.Any(x => x.Name.Equals(propName, StringComparison.OrdinalIgnoreCase))
                   && LocalUnit.Any(x => x.Name.Equals(propName, StringComparison.OrdinalIgnoreCase))
                   && EnterpriseGroup.Any(x => x.Name.Equals(propName, StringComparison.OrdinalIgnoreCase))
                   && EnterpriseUnit.Any(x => x.Name.Equals(propName, StringComparison.OrdinalIgnoreCase));
        }
    }
}