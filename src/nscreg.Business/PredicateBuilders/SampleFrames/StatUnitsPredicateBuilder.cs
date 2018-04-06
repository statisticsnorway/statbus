using System;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using nscreg.Data.Constants;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Business.PredicateBuilders.SampleFrames
{
    /// <inheritdoc />
    /// <summary>
    /// Sample frame predicate builder
    /// </summary>
    public class StatUnitsPredicateBuilder : BasePredicateBuilder<StatisticalUnit>
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
                case FieldEnum.UnitType:
                    return GetUnitTypePredicate(operation, fieldValue);
                case FieldEnum.Region:
                    return GetRegionPredicate(fieldValue, operation);
                case FieldEnum.MainActivity:
                    return GetActivityPredicate(fieldValue, operation);
                default:
                    return base.GetPredicate(field, fieldValue, operation);
            }
        }

        /// <summary>
        /// Method for type checking
        /// </summary>
        /// <param name="operation"></param>
        /// <param name="value"></param>
        /// <returns></returns>
        private Expression<Func<StatisticalUnit, bool>> GetUnitTypePredicate(OperationEnum operation, object value)
        {
            var parameter = Expression.Parameter(typeof(StatisticalUnit), "x");
            var types = GetConstantValueArray<StatUnitTypes>(value, operation)
                .Select(StatisticalUnitsTypeHelper.GetStatUnitMappingType);
            var expression = types
                .Where(x => x != typeof(EnterpriseGroup))
                .Aggregate<Type, Expression>(null, (current, type) =>
                {
                    var typeIsExp = (Expression) Expression.TypeIs(parameter, type);
                    return current == null ? typeIsExp : Expression.OrElse(typeIsExp, current);
                })??Expression.Constant(false);

            if (operation == OperationEnum.NotEqual || operation == OperationEnum.NotInList)
                expression = Expression.Not(expression);

            return Expression.Lambda<Func<StatisticalUnit, bool>>(expression, parameter);
        }

        /// <summary>
        /// Get predicate "x => x.ActivitiesUnits.Any(y => y.Activity.ActivityCategoryId == value)"
        /// </summary>
        /// <param name="fieldValue"></param>
        /// <returns></returns>
        private Expression<Func<StatisticalUnit, bool>> GetActivityPredicate(object fieldValue, OperationEnum operation)
        {
            var outerParameter = Expression.Parameter(typeof(StatisticalUnit), "x");
            var property = Expression.Property(outerParameter, nameof(StatisticalUnit.ActivitiesUnits));

            var innerParameter = Expression.Parameter(typeof(ActivityStatisticalUnit), "y");
            var categoryId = Expression.Property(innerParameter, typeof(ActivityStatisticalUnit).GetProperty(nameof(ActivityStatisticalUnit.Activity)));
            categoryId = Expression.Property(categoryId, typeof(Activity).GetProperty(nameof(Activity.ActivityCategoryId)));

            var value = GetConstantValue(fieldValue, categoryId, operation);
            var innerExpression = GetExpressionForMultiselectFields(categoryId, value, operation);

            var call = Expression.Call(typeof(Enumerable), "Any", new[] { typeof(ActivityStatisticalUnit) }, property,
                Expression.Lambda<Func<ActivityStatisticalUnit, bool>>(innerExpression, innerParameter));

            return Expression.Lambda<Func<StatisticalUnit, bool>>(call, outerParameter);
        }

        /// <summary>
        /// Get predicate "x => x.Address.RegionId operation value"
        /// </summary>
        /// <param name="fieldValue"></param>
        /// <returns></returns>
        private Expression<Func<StatisticalUnit, bool>> GetRegionPredicate(object fieldValue, OperationEnum operation)
        {
            if (OperationsRequireParsing.ContainsKey(operation))
            {
                return GetMultipleRegionsPredicate(fieldValue, operation);
            }

            var regionIdValue = int.Parse(fieldValue.ToString());

            var parameter = Expression.Parameter(typeof(StatisticalUnit), "x");
            var address = Expression.Property(parameter, nameof(StatisticalUnit.Address));
            var regionId = Expression.Property(address, nameof(Address.RegionId));
            var regionIdExpression = Expression.Equal(regionId, Expression.Constant(regionIdValue));

            return Expression.Lambda<Func<StatisticalUnit, bool>>(regionIdExpression, parameter);
        }

        private Expression<Func<StatisticalUnit, bool>> GetMultipleRegionsPredicate(object fieldValue,
            OperationEnum operation)
        {
            var regionIds = GetConstantValueArray<int>(fieldValue, operation);

            var parameter = Expression.Parameter(typeof(StatisticalUnit), "x");
            var address = Expression.Property(parameter, nameof(StatisticalUnit.Address));
            var regionId = Expression.Property(address, nameof(Address.RegionId));

            var expr = regionIds
                .Select(id => (Expression)Expression.Equal(regionId, Expression.Constant(id)))
                .Aggregate(Expression.OrElse);
            
            return Expression.Lambda<Func<StatisticalUnit, bool>>(expr, parameter);
        }


        private Expression GetExpressionForMultiselectFields(MemberExpression property, Expression value, OperationEnum operation)
        {
            switch (operation)
            {
                case OperationEnum.Equal:
                    return Expression.Equal(property, value);
                case OperationEnum.NotEqual:
                    return Expression.NotEqual(property, value);
                case OperationEnum.InList:
                    return GetInListExpression(property, value);
                case OperationEnum.NotInList:
                    return Expression.Not(GetInListExpression(property, value));
                default:
                    throw new NotImplementedException();
            }
        }
    }
}
