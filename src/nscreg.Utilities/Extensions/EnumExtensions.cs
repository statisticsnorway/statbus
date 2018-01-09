using System;
using System.Linq;
using System.Reflection;

namespace nscreg.Utilities.Extensions
{
    public class EnumExtensions
    {
        public static TEnum[] GetMembers<TEnum, TAttribute>(Func<TAttribute, bool> pred) where TAttribute : Attribute
        {
            if (!typeof(TEnum).GetTypeInfo().IsEnum)
                throw new ArgumentException("Argument must be of type Enum");
            return typeof(TEnum).GetMembers().Where(x =>
                    x.GetCustomAttribute<TAttribute>() != null && pred(x.GetCustomAttribute<TAttribute>()))
                .Select(x => Enum.Parse(typeof(TEnum), x.Name))
                .Cast<TEnum>().ToArray();
        }
    }
}
