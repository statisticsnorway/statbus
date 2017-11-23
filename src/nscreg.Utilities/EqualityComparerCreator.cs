using System;
using System.Collections.Generic;
using System.Text;

namespace nscreg.Utilities
{
    public  static class EqualityComparerCreator
    {
        public static IEqualityComparer<T> Create<T>(Func<T, T, bool> pred)
        {
            return new InternalEqualityComparer<T>(pred);
        }
        private class InternalEqualityComparer<T>: IEqualityComparer<T>
        {
            private readonly Func<T, T, bool> _pred;
            private readonly EqualityComparer<T> _comparer;

            public InternalEqualityComparer(Func<T, T, bool> pred)
            {
                _comparer = EqualityComparer<T>.Default;
                _pred = pred;
            }

            public bool Equals(T x, T y)
            {
                return _pred(x, y);
            }

            public int GetHashCode(T obj)
            {
                return _comparer.GetHashCode(obj);
            }
        }
    }
}
