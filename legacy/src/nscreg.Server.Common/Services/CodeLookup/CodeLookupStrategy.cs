using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Services.CodeLookup
{
    public class CodeLookupStrategy<T> where T : CodeLookupBase
    {
        private static readonly Dictionary<Type, Type> EntityToStrategyTypeMap = new Dictionary<Type, Type>()
        {
            [typeof(ActivityCategory)] = typeof(ActivityCodeLookupStrategy)
        };
        public virtual IQueryable<T> Filter(IQueryable<T> query, string wildcard = null, string userId = null)
        {
            var loweredwc = wildcard?.ToLower() ?? string.Empty;
            return wildcard == null
                ? query
                : query.Where(v => v.Code.StartsWith(loweredwc) || v.Name.ToLower().Contains(loweredwc));
        }

        public static CodeLookupStrategy<T> Create()
        {
            if (EntityToStrategyTypeMap.TryGetValue(typeof(T), out var type))
                return (CodeLookupStrategy<T>)Activator.CreateInstance(type);

            return new CodeLookupStrategy<T>();
        }
    }
}
