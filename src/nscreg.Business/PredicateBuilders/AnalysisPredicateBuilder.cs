using System;
using System.Linq.Expressions;
using nscreg.Utilities.Enums.Predicate;
using System.Collections.Generic;
using nscreg.Data.Entities;

namespace nscreg.Business.PredicateBuilders
{
    /// <inheritdoc />
    /// <summary>
    /// Analysis predicate builder
    /// </summary>
    /// <typeparam name="T"></typeparam>
    public class AnalysisPredicateBuilder<T> : BasePredicateBuilder<T> where T : class, IStatisticalUnit
    {
        /// <summary>
        /// Get simple analysis predicate
        /// </summary>
        /// <param name="unit">Stat unit</param>
        /// <returns>Predicate</returns>
        public Expression<Func<T, bool>> GetPredicate(T unit)
        {
            var serverPredicate = GetServerPredicate(unit);
            serverPredicate = GetPredicateOnTwoExpressions(serverPredicate, GetTypeIsPredicate(unit), ComparisonEnum.And);
            var userPredicate = GetUserPredicate(unit);

            return GetPredicateOnTwoExpressions(serverPredicate, userPredicate, ComparisonEnum.And);
        }

        /// <summary>
        /// Get filter-predicate by ours checks
        /// </summary>
        /// <param name="unit">Stat unit</param>
        /// <returns>Server predicate</returns>
        private Expression<Func<T, bool>> GetServerPredicate(T unit)
        {
            return unit.RegId >0 ? GetPredicate(FieldEnum.RegId, unit.RegId, OperationEnum.NotEqual) : True();
        }

        /// <summary>
        /// Get filter-predicate by analysis checks
        /// </summary>
        /// <param name="unit">Statistical unit</param>
        /// <returns>User predicate</returns>
        private Expression<Func<T, bool>> GetUserPredicate(T unit)
        {
            var statIdPredicate = string.IsNullOrEmpty(unit.StatId)
                ? null
                : GetPredicate(FieldEnum.StatId, unit.StatId, OperationEnum.Equal);
            var taxRegIdPredicate = string.IsNullOrEmpty(unit.TaxRegId)
                ? null
                : GetPredicate(FieldEnum.TaxRegId, unit.TaxRegId, OperationEnum.Equal);

            var statIdTaxRegIdPredicate = GetNullablePredicateOnTwoExpressions(statIdPredicate, taxRegIdPredicate, ComparisonEnum.And);

            var predicates = new List<Expression<Func<T, bool>>>
            {
                string.IsNullOrEmpty(unit.ExternalId)
                    ? null
                    : GetPredicate(FieldEnum.ExternalId, unit.ExternalId, OperationEnum.Equal),
                string.IsNullOrEmpty(unit.Name)
                    ? null
                    : GetPredicate(FieldEnum.Name, unit.Name, OperationEnum.Equal),
                unit.ActualAddressId == null
                    ? null
                    : GetPredicate(FieldEnum.ActualAddress, unit.ActualAddressId, OperationEnum.Equal)
            };

            predicates.AddRange(unit is EnterpriseGroup
                ? GetEnterpriseGroupPredicates(unit as EnterpriseGroup)
                : GetStatisticalUnitPredicate(unit as StatisticalUnit));

            Expression<Func<T, bool>> result = null;
            for (var i = 0; i < predicates.Count - 2; i++)
            {
                var leftPredicate = predicates[i];
                var rightPredicate = GetNullablePredicateOnTwoExpressions(predicates[i + 1], predicates[i + 2], ComparisonEnum.Or);

                for (var j = i + 3; j < predicates.Count; j++)
                    rightPredicate = GetNullablePredicateOnTwoExpressions(rightPredicate, predicates[j], ComparisonEnum.Or);

                var predicate = GetNullablePredicateOnTwoExpressions(leftPredicate, rightPredicate, ComparisonEnum.And);
                result = GetNullablePredicateOnTwoExpressions(result, predicate, ComparisonEnum.Or);
            }
            result = result ?? False();

            result = GetNullablePredicateOnTwoExpressions(statIdTaxRegIdPredicate, result, ComparisonEnum.Or) ?? False();
            return result;
        }
        
        private IEnumerable<Expression<Func<T, bool>>> GetEnterpriseGroupPredicates(EnterpriseGroup enterpriseGroup)
        {
            var predicates = new List<Expression<Func<T, bool>>>
            {
                string.IsNullOrEmpty(enterpriseGroup.ShortName)
                    ? null
                    : GetPredicate(FieldEnum.ShortName, enterpriseGroup.ShortName, OperationEnum.Equal),
                string.IsNullOrEmpty(enterpriseGroup.TelephoneNo)
                    ? null
                    : GetPredicate(FieldEnum.TelephoneNo, enterpriseGroup.TelephoneNo, OperationEnum.Equal),
                string.IsNullOrEmpty(enterpriseGroup.EmailAddress)
                    ? null
                    : GetPredicate(FieldEnum.EmailAddress, enterpriseGroup.EmailAddress, OperationEnum.Equal),
                string.IsNullOrEmpty(enterpriseGroup.ContactPerson)
                    ? null
                    : GetPredicate(FieldEnum.ContactPerson, enterpriseGroup.ContactPerson, OperationEnum.Equal)
            };

            return predicates;
        }

        private IEnumerable<Expression<Func<T, bool>>> GetStatisticalUnitPredicate(StatisticalUnit statisticalUnit)
        {
            var predicates = new List<Expression<Func<T, bool>>>
            {
                string.IsNullOrEmpty(statisticalUnit.ShortName)
                    ? null
                    : GetPredicate(FieldEnum.ShortName, statisticalUnit.ShortName, OperationEnum.Equal),
                string.IsNullOrEmpty(statisticalUnit.TelephoneNo)
                    ? null
                    : GetPredicate(FieldEnum.TelephoneNo, statisticalUnit.TelephoneNo, OperationEnum.Equal),
                string.IsNullOrEmpty(statisticalUnit.EmailAddress)
                    ? null
                    : GetPredicate(FieldEnum.EmailAddress, statisticalUnit.EmailAddress, OperationEnum.Equal),
            };
            

            return predicates;
        }

        private Expression<Func<T, bool>> GetNullablePredicateOnTwoExpressions(Expression<Func<T, bool>> firstExpressionLambda,
            Expression<Func<T, bool>> secondExpressionLambda, ComparisonEnum expressionComparison)
        {
            switch (expressionComparison)
            {
                case ComparisonEnum.Or:
                    return firstExpressionLambda != null && secondExpressionLambda != null ? GetPredicateOnTwoExpressions(firstExpressionLambda, secondExpressionLambda, ComparisonEnum.Or)
                        : firstExpressionLambda != null ? firstExpressionLambda
                        : secondExpressionLambda != null ? secondExpressionLambda
                        : null;
                case ComparisonEnum.And:
                    return firstExpressionLambda != null && secondExpressionLambda != null ? GetPredicateOnTwoExpressions(firstExpressionLambda, secondExpressionLambda, ComparisonEnum.And)
                        : null;
                default: throw new ArgumentException("expressionComparison");
            }
        }
    }
}
