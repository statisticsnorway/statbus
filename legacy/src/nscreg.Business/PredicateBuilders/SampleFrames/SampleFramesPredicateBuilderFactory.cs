using System;
using System.Collections.Generic;
using Microsoft.Extensions.Configuration;
using nscreg.Data;
using nscreg.Data.Entities;

namespace nscreg.Business.PredicateBuilders.SampleFrames
{
    public class SampleFramesPredicateBuilderFactory
    {
        private static readonly Dictionary<Type, object> Registered = new Dictionary<Type, object>
        {
            [typeof(StatisticalUnit)] = new StatUnitsPredicateBuilder(),
            [typeof(EnterpriseGroup)] = new EnterpriseGroupsPredicateBuilder()
        };

        public static BasePredicateBuilder<T> CreateFor<T>(NSCRegDbContext context, IConfiguration configuration) where T : class, IStatisticalUnit
        {
            if (!Registered.ContainsKey(typeof(T)))
                throw new ArgumentException($"Can't create predicate builder for type {typeof(T)}");
            var basePredicateBuilder = Registered[typeof(T)] as BasePredicateBuilder<T>;

            if (basePredicateBuilder != null)
            {
                basePredicateBuilder.DbContext = context;
                basePredicateBuilder.Configuration = configuration;
            }

            return basePredicateBuilder;
        }
    }
}
