using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Reflection;
using Microsoft.EntityFrameworkCore.Internal;
using nscreg.Data.Entities;

namespace nscreg.Server.Models.DataAccess
{
    public class DataAccessModel
    {
        public DataAccessAttributeModel[] EnterpriseGroup { get; set; }
        public DataAccessAttributeModel[] EnterpriseUnit { get; set; }
        public DataAccessAttributeModel[] LegalUnit { get; set; }
        public DataAccessAttributeModel[] LocalUnit { get; set; }

        public IEnumerable<string> ToStringCollection()
            => LegalUnit.Where(x => x.Allowed).Select(x => $"{nameof(LegalUnit)}.{x.Name}")
                .Concat(LocalUnit.Where(x => x.Allowed).Select(x => $"{nameof(LocalUnit)}.{x.Name}"))
                .Concat(
                    EnterpriseGroup.Where(x => x.Allowed)
                        .Select(x => $"{nameof(EnterpriseGroup)}.{x.Name}"))
                .Concat(
                    EnterpriseUnit.Where(x => x.Allowed).Select(x => $"{nameof(EnterpriseUnit)}.{x.Name}"));

        private static string[] GetProperties<T>() => typeof(T).GetProperties().Select(x => x.Name).ToArray();

        public override string ToString()
        {
            return ToStringCollection().Join(",");
        }

        public static DataAccessModel FromString(string dataAccess = null)
        {
            var dataAccessCollection = dataAccess?.Split(',').ToImmutableHashSet();
            Func<string, string, bool> pred = (type, prop) => dataAccessCollection?.Contains($"{type}.{prop}") ?? true;

            return new DataAccessModel
            {
                LocalUnit =
                    GetProperties<LocalUnit>()
                        .Select(x => new DataAccessAttributeModel(x, pred(nameof(LocalUnit), x)))
                        .ToArray(),
                LegalUnit =
                    GetProperties<LegalUnit>()
                        .Select(x => new DataAccessAttributeModel(x, pred(nameof(LegalUnit), x)))
                        .ToArray(),
                EnterpriseUnit =
                    GetProperties<EnterpriseUnit>()
                        .Select(x => new DataAccessAttributeModel(x, pred(nameof(EnterpriseUnit), x)))
                        .ToArray(),
                EnterpriseGroup =
                    GetProperties<EnterpriseGroup>()
                        .Select(x => new DataAccessAttributeModel(x, pred(nameof(EnterpriseGroup), x)))
                        .ToArray()
            };
        }

        public bool IsAllowedInAllTypes(string propName)
        {
            return LegalUnit.Any(x => x.Name.Equals(propName, StringComparison.OrdinalIgnoreCase))
                   && LocalUnit.Any(x => x.Name.Equals(propName, StringComparison.OrdinalIgnoreCase))
                   && EnterpriseGroup.Any(x => x.Name.Equals(propName, StringComparison.OrdinalIgnoreCase))
                   && EnterpriseUnit.Any(x => x.Name.Equals(propName, StringComparison.OrdinalIgnoreCase));
        }
    }
}