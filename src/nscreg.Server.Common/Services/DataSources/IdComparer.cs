using System.Collections.Generic;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Services.DataSources
{
    public class IdComparer<T>: IEqualityComparer<T> where T: IModelWithId
    {
        public bool Equals(T x, T y)
        {
            if (x == null && y == null)
                return true;

            if (x == null || y == null)
                return false;
            if (ReferenceEquals(x, y))
                return true;
            return x.Id != 0 && x.Id == y.Id;
        }

        public int GetHashCode(T obj)
        {
            return obj.Id.GetHashCode();
        }
    }
}
