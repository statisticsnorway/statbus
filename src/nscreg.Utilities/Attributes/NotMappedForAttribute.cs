using System;
using nscreg.Utilities.Enums;

namespace nscreg.Utilities.Attributes
{
    /// <summary>
    /// Class not attribute mappings
    /// </summary>
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
