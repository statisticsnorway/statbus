using System;
using nscreg.Utilities.Enums;

namespace nscreg.Utilities.Attributes
{
    [AttributeUsage(AttributeTargets.Property)]
    public class AsyncValidationAttribute : Attribute
    {
        public ValidationTypeEnum ValidationType { get; }

        public AsyncValidationAttribute(ValidationTypeEnum validationType)
        {
            ValidationType = validationType;
        }

    }
}
