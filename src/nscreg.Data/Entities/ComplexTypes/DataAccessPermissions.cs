using System.Collections;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using nscreg.Utilities;

namespace nscreg.Data.Entities.ComplexTypes
{
    public class DataAccessPermissions
    {
        public DataAccessPermissions()
        {
            Permissions = new List<Permission>();
        }

        public DataAccessPermissions(IEnumerable<Permission> permissions)
        {
            Permissions = permissions.ToList();
        }

        public List<Permission> Permissions { get; set; }

        public static DataAccessPermissions Combine(IEnumerable<DataAccessPermissions> permissions)
        {
            return new DataAccessPermissions(permissions
                .SelectMany(x => x.Permissions)
                .GroupBy(x => x.PropertyName)
                .Select(x => new Permission(x.Key, x.Any(y => y.CanRead), x.Any(y => y.CanWrite))));
        }

        public DataAccessPermissions ForType(string typeName)
        {
            return new DataAccessPermissions(Permissions.Where(v => v.PropertyName.StartsWith($"{typeName}.")));
        }

        public bool HasWritePermission(string name)
        {
            return Permissions.Any(x => x.PropertyName == name && x.CanWrite);
        }

        public bool HasWriteOrReadPermission(string name)
        {
            return Permissions.Any(x => x.PropertyName == name && (x.CanWrite || x.CanRead));
        }

        public ISet<string> GetReadablePropNames()
        {
            return Permissions.Where(x => x.CanRead).Select(x => x.PropertyName).ToImmutableHashSet();
        }

        public bool IsEqualTo(DataAccessPermissions another)
        {
            return another.Permissions.Except(Permissions,
                EqualityComparerCreator.Create<Permission>(
                    (x,y)=> x.PropertyName == y.PropertyName && x.CanRead == y.CanRead && x.CanWrite == y.CanWrite)).Any();
        }

        public bool HasReadPermission(string name)
        {
            return Permissions.Any(x => x.PropertyName == name && x.CanRead);
        }
    }
}
