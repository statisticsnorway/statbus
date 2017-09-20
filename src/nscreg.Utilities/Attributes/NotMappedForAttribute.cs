using System;
using nscreg.Utilities.Enums;

namespace nscreg.Utilities.Attributes
{
    /// <summary>
    /// Класс не сопоставления атрибутов
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
