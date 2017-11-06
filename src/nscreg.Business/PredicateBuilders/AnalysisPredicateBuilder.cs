using System;
using System.Linq.Expressions;
using nscreg.Utilities.Enums.Predicate;
using System.Collections.Generic;
using nscreg.Data.Entities;
using System.Reflection;
using nscreg.Data.Constants;
using System.Linq;

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
            var parentNullPredicate = GetNullPredicate(FieldEnum.ParentId, typeof(int?));
            var notSameRegIdPredicate = GetPredicate(FieldEnum.RegId, unit.RegId, OperationEnum.NotEqual);

            return GetPredicateOnTwoExpressions(parentNullPredicate, notSameRegIdPredicate, ComparisonEnum.And);
        }

        /// <summary>
        /// Get filter-predicate by analysis checks
        /// </summary>
        /// <param name="unit">Statistical unit</param>
        /// <returns>User predicate</returns>
        private Expression<Func<T, bool>> GetUserPredicate(T unit)
        {
            var statIdPredicate = unit.StatId == null
                ? GetNullPredicate(FieldEnum.StatId, typeof(string))
                : GetPredicate(FieldEnum.StatId, unit.StatId, OperationEnum.Equal);
            var taxRegIdPredicate = unit.TaxRegId == null
                ? GetNullPredicate(FieldEnum.TaxRegId, typeof(string))
                : GetPredicate(FieldEnum.TaxRegId, unit.TaxRegId, OperationEnum.Equal);
            var statIdTaxRegIdPredicate = GetPredicateOnTwoExpressions(statIdPredicate, taxRegIdPredicate, ComparisonEnum.And);

            var predicates = new List<Expression<Func<T, bool>>>
            {
                unit.ExternalId == null
                    ? GetNullPredicate(FieldEnum.ExternalId, typeof(string))
                    : GetPredicate(FieldEnum.ExternalId, unit.ExternalId, OperationEnum.Equal),
                unit.Name == null
                    ? GetNullPredicate(FieldEnum.Name, typeof(string))
                    : GetPredicate(FieldEnum.Name, unit.Name, OperationEnum.Equal),
                unit.AddressId == null
                    ? GetNullPredicate(FieldEnum.AddressId, typeof(int?))
                    : GetPredicate(FieldEnum.AddressId, unit.AddressId, OperationEnum.Equal)
            };

            predicates.AddRange(unit is EnterpriseGroup
                ? GetEnterpriseGroupPredicates(unit as EnterpriseGroup)
                : GetStatisticalUnitPredicate(unit as StatisticalUnit));

            Expression<Func<T, bool>> result = null;
            for (var i = 0; i < predicates.Count - 2; i++)
            {
                var leftPredicate = predicates[i];
                var rightPredicate = GetPredicateOnTwoExpressions(predicates[i + 1], predicates[i + 2], ComparisonEnum.Or);

                for (var j = i + 3; j < predicates.Count; j++)
                    rightPredicate = GetPredicateOnTwoExpressions(rightPredicate, predicates[j], ComparisonEnum.Or);

                var predicate = GetPredicateOnTwoExpressions(leftPredicate, rightPredicate, ComparisonEnum.And);
                result = result == null
                    ? predicate
                    : GetPredicateOnTwoExpressions(result, predicate, ComparisonEnum.Or);
            }

            result = GetPredicateOnTwoExpressions(statIdTaxRegIdPredicate, result, ComparisonEnum.Or);
            return result;
        }
        
        private IEnumerable<Expression<Func<T, bool>>> GetEnterpriseGroupPredicates(EnterpriseGroup enterpriseGroup)
        {
            var predicates = new List<Expression<Func<T, bool>>>
            {
                enterpriseGroup.ShortName == null
                    ? GetNullPredicate(FieldEnum.ShortName, typeof(string))
                    : GetPredicate(FieldEnum.ShortName, enterpriseGroup.ShortName, OperationEnum.Equal),
                enterpriseGroup.TelephoneNo == null
                    ? GetNullPredicate(FieldEnum.TelephoneNo, typeof(string))
                    : GetPredicate(FieldEnum.TelephoneNo, enterpriseGroup.TelephoneNo, OperationEnum.Equal),
                enterpriseGroup.EmailAddress == null
                    ? GetNullPredicate(FieldEnum.EmailAddress, typeof(string))
                    : GetPredicate(FieldEnum.EmailAddress, enterpriseGroup.EmailAddress, OperationEnum.Equal),
                enterpriseGroup.ContactPerson == null
                    ? GetNullPredicate(FieldEnum.ContactPerson, typeof(string))
                    : GetPredicate(FieldEnum.ContactPerson, enterpriseGroup.ContactPerson, OperationEnum.Equal)
            };

            return predicates;
        }

        private IEnumerable<Expression<Func<T, bool>>> GetStatisticalUnitPredicate(StatisticalUnit statisticalUnit)
        {
            var predicates = new List<Expression<Func<T, bool>>>
            {
                statisticalUnit.ShortName == null
                    ? GetNullPredicate(FieldEnum.ShortName, typeof(string))
                    : GetPredicate(FieldEnum.ShortName, statisticalUnit.ShortName, OperationEnum.Equal),
                statisticalUnit.TelephoneNo == null
                    ? GetNullPredicate(FieldEnum.TelephoneNo, typeof(string))
                    : GetPredicate(FieldEnum.TelephoneNo, statisticalUnit.TelephoneNo, OperationEnum.Equal),
                statisticalUnit.EmailAddress == null
                    ? GetNullPredicate(FieldEnum.EmailAddress, typeof(string))
                    : GetPredicate(FieldEnum.EmailAddress, statisticalUnit.EmailAddress, OperationEnum.Equal),
                statisticalUnit.ContactPerson == null
                    ? GetNullPredicate(FieldEnum.ContactPerson, typeof(string))
                    : GetPredicate(FieldEnum.ContactPerson, statisticalUnit.ContactPerson, OperationEnum.Equal),
                GetPersonPredicate()
            };

            return predicates;
        }

        /// <summary>
        /// Get predicate "x => x.PersonsUnits.Any(y => y.PersonType == value)"
        /// </summary>
        /// <returns></returns>
        private static Expression<Func<T, bool>> GetPersonPredicate()
        {
            var outerParameter = Expression.Parameter(typeof(StatisticalUnit), "x");
            var property = Expression.Property(outerParameter, nameof(StatisticalUnit.PersonsUnits));

            var innerParameter = Expression.Parameter(typeof(PersonStatisticalUnit), "y");
            var left = Expression.Property(innerParameter, typeof(PersonStatisticalUnit).GetProperty(nameof(PersonStatisticalUnit.PersonType)));

            var right = GetConstantValue(PersonTypes.Owner, left);
            Expression innerExpression = Expression.Equal(left, right);

            var call = Expression.Call(typeof(Enumerable), "Any", new[] { typeof(PersonStatisticalUnit) }, property,
                Expression.Lambda<Func<PersonStatisticalUnit, bool>>(innerExpression, innerParameter));

            var lambda = Expression.Lambda<Func<T, bool>>(call, outerParameter);

            return lambda;
        }
    }
}
