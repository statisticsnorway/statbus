using System;
using System.Linq.Expressions;
using System.Reflection;

namespace nscreg.Utilities.Classes
{
    internal class DataProperty<T>
    {
        public PropertyInfo Property { get; }
        public Func<T, object> Getter { get; }
        public Action<T, object> Setter { get; }

        public DataProperty(PropertyInfo property)
        {
            Property = property;
            if (property.CanRead)
            {
                Getter = MakeGetterDelegate(property);
            }
            if (property.CanWrite)
            {
                Setter = MakeSetterDelegate(property);
            }
        }

        private static Func<T, object> MakeGetterDelegate(PropertyInfo property)
        {
            var getMethod = property.GetGetMethod();
            var entity = Expression.Parameter(typeof(T));
            var getterCall = Expression.Call(entity, getMethod);
            var castToObject = Expression.Convert(getterCall, typeof(object));
            return Expression.Lambda<Func<T, object>>(castToObject, entity).Compile();
        }

        private static Action<T, object> MakeSetterDelegate(PropertyInfo property)
        {
            var setMethod = property.GetSetMethod();
            var target = Expression.Parameter(typeof(T));
            var value = Expression.Parameter(typeof(object));
            var body = Expression.Call(target, setMethod, Expression.Convert(value, property.PropertyType));
            return Expression.Lambda<Action<T, object>>(body, target, value).Compile();
        }
    }
}