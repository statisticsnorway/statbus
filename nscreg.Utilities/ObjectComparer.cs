using System;
using System.Linq;
using System.Reflection;
using nscreg.Utilities.Attributes;

namespace nscreg.Utilities
{
    public static class ObjectComparer
    {
        public static bool SequentialEquals<TValue1, TValue2>(TValue1 value1, TValue2 value2)
        {
            if (value1 == null) throw new ArgumentNullException(nameof(value1));
            if (value2 == null) throw new ArgumentNullException(nameof(value2));

            var props = typeof(TValue2).GetProperties()
                .Where(v => v.GetCustomAttribute<NotCompare>() == null)
                .ToDictionary(v => v.Name);
            foreach (var property1 in typeof(TValue1).GetProperties().Where(v => v.GetCustomAttribute<NotCompare>() == null))
            {
                PropertyInfo property2 = null;
                if (props.TryGetValue(property1.Name, out property2) && property1.PropertyType == property2.PropertyType)
                {
                    if (!Equals(property1.GetValue(value1), property2.GetValue(value2)))
                    {
                        return false;
                    }
                }
            }
            return true;
        }
    }
}
