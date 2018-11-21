using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using Microsoft.Extensions.Configuration;
using nscreg.Utilities.Enums.Predicate;
using nscreg.Business.SampleFrames;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Core;
using nscreg.Data.Entities;

namespace nscreg.Business.PredicateBuilders
{
    /// <summary>
    /// Base predicate builder
    /// </summary>
    /// <typeparam name="T"></typeparam>
    public abstract class BasePredicateBuilder<T> where T : class
    {
        protected static readonly Dictionary<OperationEnum, char> OperationsRequireParsing =
            new Dictionary<OperationEnum, char>
            {
                [OperationEnum.InRange] = '-',
                [OperationEnum.NotInRange] = '-',
                [OperationEnum.InList] = ',',
                [OperationEnum.NotInList] = ','
            };

        public NSCRegDbContext DbContext { get; set; }
        public IConfiguration Configuration { get; set; }

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
            var constantValue = GetConstantValue(fieldValue, property, operation);
            var expression = GetOperationExpression(operation, property, constantValue);
            var lambda = Expression.Lambda<Func<T, bool>>(expression, parameter);

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

        /// <summary>
        /// Getting simple predicate
        /// </summary>
        /// <param name="objectToCompare">Predicate entity</param>
        /// <returns>TypeIs Predicate</returns>
        public virtual Expression<Func<T, bool>> GetTypeIsPredicate(object objectToCompare)
        {
            var parameter = Expression.Parameter(typeof(T), "x");
            
            var expression = Expression.TypeIs(parameter, objectToCompare.GetType());
            var lambda = Expression.Lambda<Func<T, bool>>(expression, parameter);

            return lambda;
        }

        /// <summary>
        /// Merges two predicates into one
        /// </summary>
        /// <param name="firstExpressionLambda">First expression</param>
        /// <param name="secondExpressionLambda">Second expression</param>
        /// <param name="expressionComparison">Comparison</param>
        /// <returns>Predicate of two expressions</returns>
        public virtual Expression<Func<T, bool>> GetPredicateOnTwoExpressions(Expression<Func<T, bool>> firstExpressionLambda,
            Expression<Func<T, bool>> secondExpressionLambda, ComparisonEnum? expressionComparison)
        {
            BinaryExpression expression = null;
            switch (expressionComparison)
            {
                case ComparisonEnum.And:
                    expression =
                        Expression.AndAlso(
                            new SwapVisitor(firstExpressionLambda.Parameters[0], secondExpressionLambda.Parameters[0])
                                .Visit(firstExpressionLambda.Body), secondExpressionLambda.Body);
                    break;
                case ComparisonEnum.Or:
                    expression =
                        Expression.OrElse(
                            new SwapVisitor(firstExpressionLambda.Parameters[0], secondExpressionLambda.Parameters[0])
                                .Visit(firstExpressionLambda.Body), secondExpressionLambda.Body);
                    break;

            }

            var resultLambda = Expression.Lambda<Func<T, bool>>(expression, secondExpressionLambda.Parameters);

            return resultLambda;
        }

        /// <summary>
        /// Get property constant value
        /// </summary>
        /// <param name="value">Value</param>
        /// <param name="property">Property</param>
        /// <param name="operation"></param>
        /// <returns>Constant value</returns>
        protected static Expression GetConstantValue(object value, MemberExpression property, OperationEnum? operation = null)
        {
            var propertyType = ((PropertyInfo)property.Member).PropertyType;
            var converter = TypeDescriptor.GetConverter(propertyType);

            if (operation.HasValue && OperationsRequireParsing.ContainsKey(operation.Value))
            {
                var method = typeof(BasePredicateBuilder<T>).GetMethod(nameof(GetConstantValueArrayExpression),
                    BindingFlags.NonPublic | BindingFlags.Static);
                var generic = method.MakeGenericMethod(propertyType);
                return (Expression) generic.Invoke(null, new [] {value, operation});
            }

            var stringValue = value.ToString() == "0" && propertyType == typeof(Boolean) ? "false" : value.ToString() == "1" && propertyType == typeof(Boolean) ? "true" : value.ToString();
            var propertyValue = converter.ConvertFromString(stringValue);
            var constant = Expression.Constant(propertyValue);
            var constantValue = Expression.Convert(constant, propertyType);

            return constantValue;
        }

        /// <summary>
        /// Returns typed array wrapped in expsession accessor from string value
        /// </summary>
        /// <typeparam name="TProp"></typeparam>
        /// <param name="value"></param>
        /// <param name="operation"></param>
        /// <returns></returns>
        private static Expression GetConstantValueArrayExpression<TProp>(object value, OperationEnum? operation)
        {
            var arrValues = GetConstantValueArray<TProp>(value, operation);
            return Expression.Convert(Expression.Constant(arrValues), typeof(TProp).MakeArrayType());
        }

        /// <summary>
        /// Returns typed array from string value
        /// </summary>
        /// <typeparam name="TProp"></typeparam>
        /// <param name="value"></param>
        /// <param name="operation"></param>
        /// <returns></returns>
        protected static TProp[] GetConstantValueArray<TProp>(object value, OperationEnum? operation)
        {
            var converter = TypeDescriptor.GetConverter(typeof(TProp));
            var strValue = value.ToString();
            var separator = operation == OperationEnum.InRange || operation == OperationEnum.NotInRange ? '\u2014' : ',';
            var arrValues = strValue.Split(separator).Select(x => (TProp) converter.ConvertFromString(x)).ToArray();
            return arrValues;
        }

        /// <summary>
        /// Get operation expression
        /// </summary>
        /// <param name="operation">Expression operation</param>
        /// <param name="property">Expression property</param>
        /// <param name="value">Expression property value</param>
        /// <returns>Operation expression</returns>
        protected static Expression GetOperationExpression(OperationEnum operation, Expression property, Expression value)
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
                case OperationEnum.Contains:
                    return Expression.Call(property, nameof(string.Contains), null, value);
                case OperationEnum.DoesNotContain:
                    return Expression.Not(Expression.Call(property, nameof(string.Contains), null, value));
                case OperationEnum.InRange:
                    return Expression.AndAlso(
                        Expression.GreaterThanOrEqual(property,
                            Expression.ArrayIndex(value, Expression.Constant(0))),
                        Expression.LessThanOrEqual(property,
                            Expression.ArrayIndex(value, Expression.Constant(1))));
                case OperationEnum.NotInRange:
                    return Expression.Not(Expression.AndAlso(
                        Expression.GreaterThanOrEqual(property,
                            Expression.ArrayIndex(value, Expression.Constant(0))),
                        Expression.LessThanOrEqual(property,
                            Expression.ArrayIndex(value, Expression.Constant(1)))));
                case OperationEnum.InList:
                    return GetInListExpression(property, value);
                case OperationEnum.NotInList:
                    return Expression.Not(GetInListExpression(property, value));
                default:
                    throw new NotImplementedException();
            }
        }

        /// <summary>
        /// Creates ANY() expression for in list operation
        /// </summary>
        /// <param name="property"></param>
        /// <param name="value"></param>
        /// <returns></returns>
        protected static Expression GetInListExpression(Expression property, Expression value)
        {
            var querableVal = Expression.Convert(Expression.Call(typeof(Queryable), "AsQueryable", null, value),
                typeof(IQueryable<>).MakeGenericType(property.Type));
            return Expression.Call(typeof(Queryable), "Contains", new[] { property.Type }, querableVal, property);
        }

        /// <summary>
        /// Returns constant true predicate
        /// </summary>
        /// <typeparam name="T"></typeparam>
        /// <returns></returns>
        public Expression<Func<T, bool>> True() => f => true;
        /// <summary>
        /// Returns constant false predicate
        /// </summary>
        /// <typeparam name="T"></typeparam>
        /// <returns></returns>
        public Expression<Func<T, bool>> False() => f => false;
    }
}
