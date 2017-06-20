using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using AutoMapper;
using Microsoft.EntityFrameworkCore.Internal;
using nscreg.Data.Entities;
using nscreg.Server.Common.Services;

namespace nscreg.Server.Common.Models.DataAccess
{
    public class DataAccessModel
    {
        public List<DataAccessAttributeVm> EnterpriseGroup { get; set; }
        public List<DataAccessAttributeVm> EnterpriseUnit { get; set; }
        public List<DataAccessAttributeVm> LegalUnit { get; set; }
        public List<DataAccessAttributeVm> LocalUnit { get; set; }

        public IEnumerable<string> ToStringCollection(bool validate = true)
        {
            var attributes = LegalUnit.Concat(LocalUnit)
                .Concat(EnterpriseUnit)
                .Concat(EnterpriseGroup)
                .Where(v => v.Allowed)
                .Select(v => v.Name);
            if (validate)
            {
                attributes = attributes.Where(v => DataAccessAttributesProvider.Find(v) != null);
            }
            return attributes;
        }

        public override string ToString()
        {
            return ToStringCollection(false).Join(",");
        }

        public static DataAccessModel FromString(string dataAccess)
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
            return DataAccessAttributesProvider<T>.Attributes.Select(v => Mapper.Map(v, new DataAccessAttributeVm()
            {
                Allowed = dataAccess.Contains(v.Name)
            })).ToList();
        }
    }
}