using System;
using System.Linq.Expressions;
using System.Reflection;

namespace nscreg.Utilities.Classes
{
    /// <summary>
    /// Класс описывающий общее свойство данных
    /// </summary>
    public class GenericDataProperty<T, TValue>
    {
        public PropertyInfo Property { get; }
        public Func<T, TValue> Getter { get; }
        public Action<T, TValue> Setter { get; }

        public GenericDataProperty(PropertyInfo property)
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

        public GenericDataProperty(Expression<Func<T, TValue>> property) : this((PropertyInfo) ((MemberExpression)property.Body).Member)
        {
        }

        /// <summary>
        /// Метод осуществляет создание делегат геттера
        /// </summary>
        /// <param name="property">Свойство</param>
        /// <returns></returns>
        private static Func<T, TValue> MakeGetterDelegate(PropertyInfo property)
        {
            var getMethod = property.GetGetMethod();
            var entity = Expression.Parameter(typeof(T));
            var getterCall = Expression.Call(entity, getMethod);
            var castToObject = Expression.Convert(getterCall, typeof(TValue));
            return Expression.Lambda<Func<T, TValue>>(castToObject, entity).Compile();
        }

        /// <summary>
        /// Метод осуществляет создание делегат сеттера
        /// </summary>
        /// <param name="property">Свойство</param>
        /// <returns></returns>
        private static Action<T, TValue> MakeSetterDelegate(PropertyInfo property)
        {
            var setMethod = property.GetSetMethod();
            var target = Expression.Parameter(typeof(T));
            var value = Expression.Parameter(typeof(TValue));
            var body = Expression.Call(target, setMethod, Expression.Convert(value, property.PropertyType));
            return Expression.Lambda<Action<T, TValue>>(body, target, value).Compile();
        }
    }
}
