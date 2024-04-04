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
    public class EnterpriseGroupsPredicateBuilder : BasePredicateBuilder<EnterpriseGroup>
    {
        /// <inheritdoc />
        /// <summary>
        /// Get sample frame predicate
        /// </summary>
        /// <param name="field">Predicate entity field</param>
        /// <param name="fieldValue">Predicate field value</param>
        /// <param name="operation">Predicate operation</param>
        /// <returns>Predicate</returns>
        public override Expression<Func<EnterpriseGroup, bool>> GetPredicate(
            FieldEnum field,
            object fieldValue,
            OperationEnum operation)
        {
            switch (field)
            {
                case FieldEnum.UnitType:
                    return GetUnitTypePredicate(operation, fieldValue);
                case FieldEnum.Region:
                case FieldEnum.MainActivity:
                    return False();
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
        private Expression<Func<EnterpriseGroup, bool>> GetUnitTypePredicate(OperationEnum operation, object value)
        {
            var parameter = Expression.Parameter(typeof(EnterpriseGroup), "x");
            var types = GetConstantValueArray<StatUnitTypes>(value, operation)
                .Select(StatisticalUnitsTypeHelper.GetStatUnitMappingType);

            Expression expression = Expression.Constant(types.Any(x => x == typeof(EnterpriseGroup)));

            if (operation == OperationEnum.NotEqual || operation == OperationEnum.NotInList)
                expression = Expression.Not(expression);

            return Expression.Lambda<Func<EnterpriseGroup, bool>>(expression, parameter);
        }

    }
}
