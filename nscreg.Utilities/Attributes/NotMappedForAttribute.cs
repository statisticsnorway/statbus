using System;
using nscreg.Utilities.Enums;

namespace nscreg.Utilities.Attributes
{
    [AttributeUsage(AttributeTargets.Property)]
    public class NotMappedForAttribute : Attribute
    {
        public ActionsEnum Actions { get; }
        public NotMappedForAttribute(ActionsEnum actions)
        {
            Actions = actions;
        }
    }
}