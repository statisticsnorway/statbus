using System;
using System.Collections.Generic;
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

        public static BasePredicateBuilder<T> CreateFor<T>() where T : class, IStatisticalUnit
        {
            if (!Registered.ContainsKey(typeof(T)))
                throw new ArgumentException($"Can't create predicate builder for type {typeof(T)}");
            return Registered[typeof(T)] as BasePredicateBuilder<T>;
        }
    }
}
