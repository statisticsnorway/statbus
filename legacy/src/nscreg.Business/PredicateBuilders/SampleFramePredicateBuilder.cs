using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using nscreg.Data.Constants;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Business.PredicateBuilders
{
    /// <inheritdoc />
    /// <summary>
    /// Sample frame predicate builder
    /// </summary>
    public class SampleFramePredicateBuilder<T> : BasePredicateBuilder<T> where T : class, IStatisticalUnit
    {
        /// <inheritdoc />
        /// <summary>
        /// Get sample frame predicate
        /// </summary>
        /// <param name="field">Predicate entity field</param>
        /// <param name="fieldValue">Predicate field value</param>
        /// <param name="operation">Predicate operation</param>
        /// <returns>Predicate</returns>
        public override Expression<Func<T, bool>> GetPredicate(
            FieldEnum field,
            object fieldValue,
            OperationEnum operation)
        {
            var isStatUnit = typeof(T) == typeof(StatisticalUnit);
            switch (field)
            {
                case FieldEnum.UnitType:
                    return GetUnitTypePredicate(operation, fieldValue, isStatUnit);
                case FieldEnum.Region:
                    return isStatUnit ? GetRegionPredicate(fieldValue) : False();
                case FieldEnum.MainActivity:
                    return isStatUnit ? GetActivityPredicate(fieldValue): False();
                default:
                    return base.GetPredicate(field, fieldValue, operation);
            }
        }

        /// <summary>
        /// Method for type checking
        /// </summary>
        /// <param name="operation"></param>
        /// <param name="value"></param>
        /// <param name="isStatUnit"></param>
        /// <returns></returns>
        private Expression<Func<T, bool>> GetUnitTypePredicate(OperationEnum operation, object value, bool isStatUnit)
        {
            var parameter = Expression.Parameter(typeof(T), "x");
            var types = GetConstantValueArray<StatUnitTypes>(value, operation)
                .Select(StatisticalUnitsTypeHelper.GetStatUnitMappingType);
            Expression expression = Expression.Constant(false);

            if (isStatUnit)
                expression = types
                    .Where(x => x != typeof(EnterpriseGroup))
                    .Aggregate(expression, (current, type) =>
                    {
                        var typeIsExp = (Expression) Expression.TypeIs(parameter, type);
                        return current == null ? typeIsExp : Expression.OrElse(typeIsExp, current);
                    });
            else
                expression = Expression.Constant(types.Any(x => x == typeof(EnterpriseGroup)));


            if (operation == OperationEnum.NotEqual || operation == OperationEnum.NotInList)
                expression = Expression.Not(expression);

            return Expression.Lambda<Func<T, bool>>(expression, parameter);
        }

        /// <summary>
        /// Get predicate "x => x.ActivitiesUnits.Any(y => y.Activity.ActivityCategoryId == value)"
        /// </summary>
        /// <param name="fieldValue"></param>
        /// <returns></returns>
        private static Expression<Func<T, bool>> GetActivityPredicate(object fieldValue)
        {
            var outerParameter = Expression.Parameter(typeof(T), "x");
            var property = Expression.Property(outerParameter, nameof(StatisticalUnit.ActivitiesUnits));

            var innerParameter = Expression.Parameter(typeof(ActivityStatisticalUnit), "y");
            var left = Expression.Property(innerParameter, typeof(ActivityStatisticalUnit).GetProperty(nameof(ActivityStatisticalUnit.Activity)));
            left = Expression.Property(left, typeof(Activity).GetProperty(nameof(Activity.ActivityCategoryId)));

            var right = GetConstantValue(fieldValue, left);
            Expression innerExpression = Expression.Equal(left, right);

            var call = Expression.Call(typeof(Enumerable), "Any", new[] { typeof(ActivityStatisticalUnit) }, property,
                Expression.Lambda<Func<ActivityStatisticalUnit, bool>>(innerExpression, innerParameter));

            var lambda = Expression.Lambda<Func<T, bool>>(call, outerParameter);

            return lambda;
        }

        /// <summary>
        /// Get predicate "x => x.Address.Region.Code.StartsWith(value)"
        /// </summary>
        /// <param name="fieldValue"></param>
        /// <returns></returns>
        private static Expression<Func<T, bool>> GetRegionPredicate(object fieldValue)
        {
            var parameter = Expression.Parameter(typeof(StatisticalUnit), "x");
            var property = Expression.Property(parameter, typeof(StatisticalUnit).GetProperty("Address"));
            property = Expression.Property(property, typeof(Address).GetProperty("Region"));
            property = Expression.Property(property, typeof(Region).GetProperty("Code"));
            var constantValue = GetConstantValue(fieldValue, property);

            var method = typeof(string).GetMethod("StartsWith", new[] { typeof(string) });
            var startsWith = Expression.Call(property, method, constantValue);

            return Expression.Lambda<Func<T, bool>>(startsWith, parameter);
        }
    }
}
