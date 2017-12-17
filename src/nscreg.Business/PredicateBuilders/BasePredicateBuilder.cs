using System;
using System.ComponentModel;
using System.Linq.Expressions;
using System.Reflection;
using nscreg.Utilities.Enums.Predicate;
using nscreg.Business.SampleFrames;

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

                case ComparisonEnum.AndNot:
                    var andNegatedExpression =
                        Expression.Lambda<Func<T, bool>>(Expression.Not(secondExpressionLambda.Body),
                            secondExpressionLambda.Parameters[0]);
                    expression =
                        Expression.AndAlso(
                            new SwapVisitor(firstExpressionLambda.Parameters[0], andNegatedExpression.Parameters[0])
                                .Visit(firstExpressionLambda.Body), andNegatedExpression.Body);
                    break;

                case ComparisonEnum.Or:
                    expression =
                        Expression.OrElse(
                            new SwapVisitor(firstExpressionLambda.Parameters[0], secondExpressionLambda.Parameters[0])
                                .Visit(firstExpressionLambda.Body), secondExpressionLambda.Body);
                    break;

                case ComparisonEnum.OrNot:
                    var orNegatedExpression =
                        Expression.Lambda<Func<T, bool>>(Expression.Not(secondExpressionLambda.Body),
                            secondExpressionLambda.Parameters[0]);
                    expression =
                        Expression.OrElse(
                            new SwapVisitor(firstExpressionLambda.Parameters[0], orNegatedExpression.Parameters[0])
                                .Visit(firstExpressionLambda.Body), orNegatedExpression.Body);
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
        /// <returns>Constant value</returns>
        protected static Expression GetConstantValue(object value, MemberExpression property)
        {
            var propertyType = ((PropertyInfo)property.Member).PropertyType;
            var converter = TypeDescriptor.GetConverter(propertyType);
            var propertyValue = converter.ConvertFromString(value.ToString());
            var constant = Expression.Constant(propertyValue);
            var constantValue = Expression.Convert(constant, propertyType);

            return constantValue;
        }

        /// <summary>
        /// Get operation expression
        /// </summary>
        /// <param name="operation">Expression operation</param>
        /// <param name="property">Expression property</param>
        /// <param name="value">Expression property value</param>
        /// <returns>Operation expression</returns>
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
