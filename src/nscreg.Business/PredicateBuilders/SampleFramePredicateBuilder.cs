using System;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Business.PredicateBuilders
{
    /// <inheritdoc />
    /// <summary>
    /// Sample frame predicate builder
    /// </summary>
    public class SampleFramePredicateBuilder : BasePredicateBuilder<StatisticalUnit>
    {
        /// <inheritdoc />
        /// <summary>
        /// Get sample frame predicate
        /// </summary>
        /// <param name="field">Predicate entity field</param>
        /// <param name="fieldValue">Predicate field value</param>
        /// <param name="operation">Predicate operation</param>
        /// <returns>Predicate</returns>
        public override Expression<Func<StatisticalUnit, bool>> GetPredicate(
            FieldEnum field,
            object fieldValue,
            OperationEnum operation)
        {
            switch (field)
            {
                case FieldEnum.Region:
                    return GetRegionPredicate(fieldValue);
                case FieldEnum.MainActivity:
                    return GetActivityPredicate(fieldValue);
                default:
                    return base.GetPredicate(field, fieldValue, operation);
            }
        }

        /// <summary>
        /// Get predicate "x => x.ActivitiesUnits.Any(y => y.Activity.ActivityCategoryId == value)"
        /// </summary>
        /// <param name="fieldValue"></param>
        /// <returns></returns>
        private static Expression<Func<StatisticalUnit, bool>> GetActivityPredicate(object fieldValue)
        {
            var outerParameter = Expression.Parameter(typeof(StatisticalUnit), "x");
            var property = Expression.Property(outerParameter, nameof(StatisticalUnit.ActivitiesUnits));

            var innerParameter = Expression.Parameter(typeof(ActivityStatisticalUnit), "y");
            var left = Expression.Property(innerParameter, typeof(ActivityStatisticalUnit).GetProperty(nameof(ActivityStatisticalUnit.Activity)));
            left = Expression.Property(left, typeof(Activity).GetProperty(nameof(Activity.ActivityCategoryId)));

            var right = GetConstantValue(fieldValue, left);
            Expression innerExpression = Expression.Equal(left, right);

            var call = Expression.Call(typeof(Enumerable), "Any", new[] { typeof(ActivityStatisticalUnit) }, property,
                Expression.Lambda<Func<ActivityStatisticalUnit, bool>>(innerExpression, innerParameter));

            var lambda = Expression.Lambda<Func<StatisticalUnit, bool>>(call, outerParameter);

            return lambda;
        }

        /// <summary>
        /// Get predicate "x => x.Address.Region.Code.StartsWith(value)"
        /// </summary>
        /// <param name="fieldValue"></param>
        /// <returns></returns>
        private static Expression<Func<StatisticalUnit, bool>> GetRegionPredicate(object fieldValue)
        {
            var parameter = Expression.Parameter(typeof(StatisticalUnit), "x");
            var property = Expression.Property(parameter, typeof(StatisticalUnit).GetProperty("Address"));
            property = Expression.Property(property, typeof(Address).GetProperty("Region"));
            property = Expression.Property(property, typeof(Region).GetProperty("Code"));
            var constantValue = GetConstantValue(fieldValue, property);

            var method = typeof(string).GetMethod("StartsWith", new[] { typeof(string) });
            var startsWith = Expression.Call(property, method, constantValue);

            var lambda = Expression.Lambda<Func<StatisticalUnit, bool>>(startsWith, parameter);
            return lambda;
        }
    }
}
