using System.Collections.Generic;

namespace nscreg.Utilities.Extensions
{
    public static class DictionaryExtensions
    {
        public static IDictionary<TKey, TValue> AddMissingKeys<TKey, TValue>(this IDictionary<TKey, TValue> src,
            IEnumerable<TKey> keys)
        {
            var result = new Dictionary<TKey, TValue>();

            foreach (var key in keys)
                result[key] = src.TryGetValue(key, out var value) ? value : default(TValue);

            return result;
        }
    }
}
