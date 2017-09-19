using System;

namespace nscreg.Server.TestUI.Commons
{
    [AttributeUsage(AttributeTargets.Method)]
    public class OrderAttribute : Attribute
    {
        public OrderAttribute(int priority)
        {
            Priority = priority;
        }

        // ReSharper disable once UnusedAutoPropertyAccessor.Global
        public int Priority { get; private set; }
    }
}
