using System;
using System.ComponentModel;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Business.PredicateBuilders
{
    /// <summary>
    /// Base predicate builder
    /// </summary>
    /// <typeparam name="T"></typeparam>
    public abstract class BasePredicateBuilder<T> where T : class
    {
        /// <summary>
        /// Getting simple predicate
        /// </summary>
        /// <param name="field">Predicate entity field</param>
        /// <param name="fieldValue">Predicate field value</param>
        /// <param name="operation">Predicate operation</param>
        /// <returns>Predicate</returns>
        public virtual Expression<Func<T, bool>> GetPredicate(FieldEnum field, object fieldValue, OperationEnum operation)
        {
            var parameter = Expression.Parameter(typeof(T), "x");
            var property = Expression.Property(parameter, field.ToString());
            var constantValue = GetConstantValue(fieldValue, property);
            var lambda = Expression.Lambda<Func<T, bool>>(GetOperationExpression(operation, property, constantValue), parameter);

            return lambda;
        }

        /// <summary>
        /// Getting null-predicate
        /// </summary>
        /// <param name="field">Predicate field</param>
        /// <param name="fieldType">Predicate field type</param>
        /// <returns>Null-predicate</returns>
        public virtual Expression<Func<T, bool>> GetNullPredicate(FieldEnum field, Type fieldType)
        {
            var parameter = Expression.Parameter(typeof(T), "x");
            var property = Expression.Property(parameter, field.ToString());
            var constantValue = Expression.Constant(null, fieldType);

            var expression = Expression.Equal(property, constantValue);
            var lambda = Expression.Lambda<Func<T, bool>>(expression, parameter);

            return lambda;
        }


        protected static Expression GetConstantValue(object value, MemberExpression property)
        {
            var propertyType = ((PropertyInfo)property.Member).PropertyType;
            var converter = TypeDescriptor.GetConverter(propertyType);
            var propertyValue = converter.ConvertFromString(value.ToString());
            var constant = Expression.Constant(propertyValue);
            var constantValue = Expression.Convert(constant, propertyType);

            return constantValue;
        }

        protected static BinaryExpression GetOperationExpression(OperationEnum operation, Expression property, Expression value)
        {
            switch (operation)
            {
                case OperationEnum.Equal:
                    return Expression.Equal(property, value);
                case OperationEnum.LessThan:
                    return Expression.LessThan(property, value);
                case OperationEnum.LessThanOrEqual:
                    return Expression.LessThanOrEqual(property, value);
                case OperationEnum.GreaterThan:
                    return Expression.GreaterThan(property, value);
                case OperationEnum.GreaterThanOrEqual:
                    return Expression.GreaterThanOrEqual(property, value);
                case OperationEnum.NotEqual:
                    return Expression.NotEqual(property, value);
                default:
                    return null;
            }
        }
    }
}
