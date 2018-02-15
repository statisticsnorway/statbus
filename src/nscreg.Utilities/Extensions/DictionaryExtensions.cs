using System;
using System.Collections.Generic;

namespace nscreg.Utilities.Extensions
{
    public static class DictionaryExtensions
    {
       public static TValue GetValueOrDefault<TKey, TValue>(this IDictionary<TKey, TValue> src, TKey key, TValue defaultVal = default(TValue))
        {
            if (src == null)
                throw new ArgumentNullException(nameof(src));
            return key != null && src.TryGetValue(key, out var value) ? value : defaultVal;
        }
    }
}
